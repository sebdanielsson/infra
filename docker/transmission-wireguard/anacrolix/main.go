// Command anacrolix is a small headless BitTorrent daemon built on
// github.com/anacrolix/torrent, deployed next to Transmission to try the
// library on hogsmeade.
//
// It runs in the WireGuard container's network namespace, keeps a NAT-PMP
// port mapping open on the VPN gateway and listens on the mapped port. Add
// torrents by dropping .torrent or .magnet files into the watch directory,
// or by POSTing a magnet URI or .torrent file to /add.
package main

import (
	"bytes"
	"cmp"
	"context"
	"crypto/subtle"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"syscall"
	"text/tabwriter"
	"time"

	g "github.com/anacrolix/generics"
	"github.com/anacrolix/torrent"
	"github.com/anacrolix/torrent/metainfo"
	"github.com/anacrolix/torrent/storage"
	natpmp "github.com/jackpal/go-nat-pmp"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

type config struct {
	gateway     net.IP
	httpAddr    string
	httpUser    string
	httpPass    string
	dataDir     string // SSD: piece completion DB and saved .torrent/.magnet files
	downloadDir string // torrent payloads
	watchDir    string
	disableMmap bool
}

func loadConfig() config {
	gw := net.ParseIP(os.Getenv("NATPMP_GATEWAY"))
	if gw == nil {
		log.Fatal("NATPMP_GATEWAY must be an IP address")
	}
	return config{
		gateway:     gw,
		httpAddr:    cmp.Or(os.Getenv("HTTP_ADDR"), ":9092"),
		httpUser:    os.Getenv("HTTP_USER"),
		httpPass:    os.Getenv("HTTP_PASS"),
		dataDir:     cmp.Or(os.Getenv("DATA_DIR"), "/data"),
		downloadDir: cmp.Or(os.Getenv("DOWNLOAD_DIR"), "/downloads/files"),
		watchDir:    cmp.Or(os.Getenv("WATCH_DIR"), "/downloads/watch"),
		disableMmap: os.Getenv("DISABLE_MMAP") == "true",
	}
}

func main() {
	cfg := loadConfig()
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, os.Interrupt)
	defer stop()

	for _, dir := range []string{
		filepath.Join(cfg.dataDir, "torrents"),
		filepath.Join(cfg.dataDir, "magnets"),
		cfg.downloadDir,
		cfg.watchDir,
	} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			log.Fatal(err)
		}
	}

	pm := &portMapper{client: natpmp.NewClientWithTimeout(cfg.gateway, 10*time.Second)}
	port, lifetime, err := pm.mapWithRetry(ctx)
	if err != nil {
		log.Fatalf("NAT-PMP on %s: %v", cfg.gateway, err)
	}
	log.Printf("NAT-PMP: gateway %s forwards port %d (tcp+udp, %ds lifetime)", cfg.gateway, port, lifetime)

	pc, err := storage.NewBoltPieceCompletion(cfg.dataDir)
	if err != nil {
		log.Fatalf("piece completion db: %v", err)
	}
	store := storage.NewFileOpts(storage.NewFileClientOpts{
		ClientBaseDir:   cfg.downloadDir,
		PieceCompletion: pc,
		DisableMmap:     cfg.disableMmap,
	})
	tc := torrent.NewDefaultClientConfig()
	tc.DataDir = cfg.downloadDir
	tc.DefaultStorage = store
	tc.ListenPort = int(port)
	tc.Seed = true
	// Port forwarding is the NAT-PMP mapping above; inside the tunnel there
	// is no UPnP router to talk to.
	tc.NoDefaultPortForwarding = true
	// The tunnel only carries IPv4 (AllowedIPs = 0.0.0.0/0).
	tc.DisableIPv6 = true
	cl, err := torrent.NewClient(tc)
	if err != nil {
		log.Fatalf("torrent client: %v", err)
	}

	d := &daemon{cfg: cfg, cl: cl, pc: pc, port: port, rates: map[metainfo.Hash]rate{}}
	d.loadSaved()
	go d.watch(ctx)
	go d.sampleRates(ctx)

	// anacrolix binds its listeners once, at startup. If the VPN hands out
	// a different port, exit and let Docker restart us on the new one.
	mappingLost := make(chan error, 1)
	go func() { mappingLost <- pm.keep(ctx, port, lifetime) }()

	prometheus.MustRegister(collector{d})
	srv := &http.Server{Addr: cfg.httpAddr, Handler: d.routes(), ReadHeaderTimeout: 10 * time.Second}
	go func() {
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("http: %v", err)
		}
	}()
	log.Printf("listening for peers on :%d, http on %s", port, cfg.httpAddr)

	exitCode := 0
	select {
	case <-ctx.Done():
		log.Print("shutting down")
	case err := <-mappingLost:
		log.Printf("NAT-PMP: %v; restarting to listen on the new port", err)
		exitCode = 1
	}
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = srv.Shutdown(shutdownCtx)
	cl.Close()
	if err := store.Close(); err != nil {
		log.Printf("closing storage: %v", err)
	}
	os.Exit(exitCode)
}

// portMapper keeps one TCP and one UDP mapping open on the VPN gateway.
// Like ProtonVPN's own instructions, it asks for internal port 0 and the
// gateway forwards the external port it picks to that same local port.
type portMapper struct{ client *natpmp.Client }

const requestedLifetime = 60 // seconds

func (p *portMapper) mapPort(want uint16) (port uint16, lifetime int, err error) {
	tcp, err := p.client.AddPortMapping("tcp", 0, int(want), requestedLifetime)
	if err != nil {
		return 0, 0, fmt.Errorf("tcp mapping: %w", err)
	}
	udp, err := p.client.AddPortMapping("udp", 0, int(tcp.MappedExternalPort), requestedLifetime)
	if err != nil {
		return 0, 0, fmt.Errorf("udp mapping: %w", err)
	}
	if udp.MappedExternalPort != tcp.MappedExternalPort {
		log.Printf("NAT-PMP: udp got port %d, tcp got %d; uTP and DHT won't be reachable inbound",
			udp.MappedExternalPort, tcp.MappedExternalPort)
	}
	return tcp.MappedExternalPort, int(tcp.PortMappingLifetimeInSeconds), nil
}

// mapWithRetry covers the tunnel still coming up when the container starts.
func (p *portMapper) mapWithRetry(ctx context.Context) (uint16, int, error) {
	var err error
	for range 10 {
		var port uint16
		var lifetime int
		if port, lifetime, err = p.mapPort(0); err == nil {
			return port, lifetime, nil
		}
		log.Printf("NAT-PMP: %v; retrying", err)
		select {
		case <-ctx.Done():
			return 0, 0, ctx.Err()
		case <-time.After(3 * time.Second):
		}
	}
	return 0, 0, err
}

// keep renews the mapping until ctx ends, and returns an error once the
// gateway stops giving us the port we listen on.
func (p *portMapper) keep(ctx context.Context, port uint16, lifetime int) error {
	failures := 0
	for {
		wait := max(time.Duration(lifetime)*time.Second-15*time.Second, 10*time.Second)
		if failures > 0 {
			wait = 5 * time.Second
		}
		select {
		case <-ctx.Done():
			return nil
		case <-time.After(wait):
		}
		got, l, err := p.mapPort(port)
		switch {
		case err != nil:
			failures++
			log.Printf("NAT-PMP renewal failed (%d in a row): %v", failures, err)
			if failures >= 6 {
				return fmt.Errorf("renewal kept failing: %w", err)
			}
		case got != port:
			return fmt.Errorf("gateway moved the mapping from port %d to %d", port, got)
		default:
			failures, lifetime = 0, l
		}
	}
}

type rate struct{ down, up float64 } // bytes per second of payload

type daemon struct {
	cfg  config
	cl   *torrent.Client
	pc   storage.PieceCompletion
	port uint16

	mu    sync.Mutex
	rates map[metainfo.Hash]rate
	total rate
}

func (d *daemon) savedPath(kind string, ih metainfo.Hash) string {
	return filepath.Join(d.cfg.dataDir, kind+"s", ih.HexString()+"."+kind)
}

// loadSaved re-adds everything added before a restart.
func (d *daemon) loadSaved() {
	for _, kind := range []string{"torrent", "magnet"} {
		paths, _ := filepath.Glob(filepath.Join(d.cfg.dataDir, kind+"s", "*."+kind))
		for _, p := range paths {
			if _, err := d.addFile(p); err != nil {
				log.Printf("re-adding %s: %v", p, err)
			}
		}
	}
}

// addFile adds a .torrent or .magnet file.
func (d *daemon) addFile(path string) (*torrent.Torrent, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	return d.add(b)
}

// add takes a magnet URI or the contents of a .torrent file.
func (d *daemon) add(b []byte) (*torrent.Torrent, error) {
	if s := strings.TrimSpace(string(b)); strings.HasPrefix(s, "magnet:") {
		return d.addMagnet(s)
	}
	mi, err := metainfo.Load(bytes.NewReader(b))
	if err != nil {
		return nil, fmt.Errorf("neither a magnet URI nor a torrent file: %w", err)
	}
	t, err := d.cl.AddTorrent(mi)
	if err != nil {
		return nil, err
	}
	if err := writeFileAtomic(d.savedPath("torrent", t.InfoHash()), b); err != nil {
		return nil, err
	}
	d.start(t)
	return t, nil
}

func (d *daemon) addMagnet(uri string) (*torrent.Torrent, error) {
	t, err := d.cl.AddMagnet(uri)
	if err != nil {
		return nil, err
	}
	magnetPath := d.savedPath("magnet", t.InfoHash())
	if err := writeFileAtomic(magnetPath, []byte(uri+"\n")); err != nil {
		return nil, err
	}
	// Once the metadata arrives, keep it as a .torrent so a restart doesn't
	// have to fetch it from peers again.
	go func() {
		<-t.GotInfo()
		var buf bytes.Buffer
		mi := t.Metainfo()
		if err := mi.Write(&buf); err != nil {
			log.Printf("%s: encoding metainfo: %v", t.Name(), err)
			return
		}
		if err := writeFileAtomic(d.savedPath("torrent", t.InfoHash()), buf.Bytes()); err != nil {
			log.Printf("%s: saving metainfo: %v", t.Name(), err)
			return
		}
		_ = os.Remove(magnetPath)
	}()
	d.start(t)
	return t, nil
}

func (d *daemon) start(t *torrent.Torrent) {
	go func() {
		<-t.GotInfo()
		t.DownloadAll()
		log.Printf("downloading %s (%s)", t.Name(), t.InfoHash().HexString())
	}()
}

// watch polls the watch directory; it is on ZFS over a bind mount, where
// inotify is not worth relying on.
func (d *daemon) watch(ctx context.Context) {
	tick := time.NewTicker(5 * time.Second)
	defer tick.Stop()
	for {
		entries, err := os.ReadDir(d.cfg.watchDir)
		if err != nil {
			log.Printf("watch dir: %v", err)
		}
		for _, e := range entries {
			ext := strings.ToLower(filepath.Ext(e.Name()))
			if e.IsDir() || (ext != ".torrent" && ext != ".magnet") {
				continue
			}
			// Skip files that may still be being copied in.
			if info, err := e.Info(); err != nil || time.Since(info.ModTime()) < 3*time.Second {
				continue
			}
			p := filepath.Join(d.cfg.watchDir, e.Name())
			if _, err := d.addFile(p); err != nil {
				log.Printf("watch: %s: %v", e.Name(), err)
				_ = os.Rename(p, p+".failed")
				continue
			}
			_ = os.Remove(p)
		}
		select {
		case <-ctx.Done():
			return
		case <-tick.C:
		}
	}
}

// sampleRates turns the payload byte counters into per-second rates for the
// summary page. Prometheus gets the raw counters instead.
func (d *daemon) sampleRates(ctx context.Context) {
	const every = 5 * time.Second
	type sample struct{ down, up int64 }
	prev := map[metainfo.Hash]sample{}
	tick := time.NewTicker(every)
	defer tick.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-tick.C:
		}
		rates := map[metainfo.Hash]rate{}
		var total rate
		for _, t := range d.cl.Torrents() {
			st := t.Stats()
			cur := sample{st.BytesReadUsefulData.Int64(), st.BytesWrittenData.Int64()}
			if p, ok := prev[t.InfoHash()]; ok {
				r := rate{float64(cur.down-p.down) / every.Seconds(), float64(cur.up-p.up) / every.Seconds()}
				rates[t.InfoHash()] = r
				total.down += r.down
				total.up += r.up
			}
			prev[t.InfoHash()] = cur
		}
		d.mu.Lock()
		d.rates, d.total = rates, total
		d.mu.Unlock()
	}
}

func (d *daemon) routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) { io.WriteString(w, "ok\n") })
	mux.Handle("GET /metrics", promhttp.Handler())
	mux.Handle("GET /{$}", d.auth(http.HandlerFunc(d.summary)))
	mux.Handle("GET /status", d.auth(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		d.cl.WriteStatus(w)
	})))
	mux.Handle("POST /add", d.auth(http.HandlerFunc(d.handleAdd)))
	mux.Handle("POST /remove", d.auth(http.HandlerFunc(d.handleRemove)))
	return mux
}

func (d *daemon) auth(next http.Handler) http.Handler {
	if d.cfg.httpUser == "" {
		return next
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		u, p, ok := r.BasicAuth()
		if !ok || subtle.ConstantTimeCompare([]byte(u), []byte(d.cfg.httpUser)) != 1 ||
			subtle.ConstantTimeCompare([]byte(p), []byte(d.cfg.httpPass)) != 1 {
			w.Header().Set("WWW-Authenticate", `Basic realm="anacrolix"`)
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// handleAdd accepts a magnet URI or a .torrent file as the request body:
//
//	curl -u user:pass --data-binary 'magnet:?xt=...' https://anacrolix.<tailnet>/add
//	curl -u user:pass --data-binary @file.torrent https://anacrolix.<tailnet>/add
func (d *daemon) handleAdd(w http.ResponseWriter, r *http.Request) {
	b, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 16<<20))
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	t, err := d.add(b)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	fmt.Fprintf(w, "added %s\n", t.InfoHash().HexString())
}

// handleRemove drops the torrent whose infohash is the request body, and with
// ?files=delete also deletes its downloaded data:
//
//	curl -u user:pass --data-binary <infohash> 'https://anacrolix.<tailnet>/remove?files=delete'
func (d *daemon) handleRemove(w http.ResponseWriter, r *http.Request) {
	b, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 1<<10))
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	var ih metainfo.Hash
	if err := ih.FromHexString(strings.TrimSpace(string(b))); err != nil {
		http.Error(w, "body must be a hex infohash", http.StatusBadRequest)
		return
	}
	t, ok := d.cl.Torrent(ih)
	if !ok {
		http.Error(w, "no such torrent", http.StatusNotFound)
		return
	}
	deleteFiles := r.URL.Query().Get("files") == "delete"
	var dataPath string
	if deleteFiles && t.Info() != nil {
		// Payloads live at <download dir>/<torrent name>. Refuse anything that
		// would resolve somewhere else.
		dataPath = filepath.Join(d.cfg.downloadDir, t.Name())
		if base := filepath.Base(dataPath); base == "." || base == ".." ||
			filepath.Dir(dataPath) != filepath.Clean(d.cfg.downloadDir) {
			http.Error(w, "refusing to delete files for torrent name "+t.Name(), http.StatusInternalServerError)
			return
		}
	}
	numPieces := t.NumPieces()
	t.Drop()
	for _, kind := range []string{"torrent", "magnet"} {
		_ = os.Remove(d.savedPath(kind, ih))
	}
	if dataPath != "" {
		// Incomplete single-file torrents are kept as <name>.part.
		for _, p := range []string{dataPath, dataPath + ".part"} {
			if err := os.RemoveAll(p); err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
		}
		// Forget the stored completion so a re-add verifies instead of
		// trusting pieces that are gone.
		for i := range numPieces {
			_ = d.pc.Set(metainfo.PieceKey{InfoHash: ih, Index: i}, g.None[bool]())
		}
	}
	fmt.Fprintf(w, "removed %s\n", ih.HexString())
}

func (d *daemon) summary(w http.ResponseWriter, _ *http.Request) {
	d.mu.Lock()
	rates, total := d.rates, d.total
	d.mu.Unlock()
	st := d.cl.Stats()
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	fmt.Fprintf(w, "anacrolix/torrent on peer port %d (NAT-PMP via %s)\n", d.port, d.cfg.gateway)
	fmt.Fprintf(w, "down %s/s  up %s/s  peers %d active / %d known  seeders %d\n\n",
		human(total.down), human(total.up), st.ActivePeers, st.TotalPeers, st.ConnectedSeeders)

	torrents := d.cl.Torrents()
	slices.SortFunc(torrents, func(a, b *torrent.Torrent) int { return strings.Compare(a.Name(), b.Name()) })
	tw := tabwriter.NewWriter(w, 0, 0, 2, ' ', 0)
	fmt.Fprintln(tw, "NAME\tDONE\tSIZE\tDOWN/s\tUP/s\tPEERS\tSEEDS\tINFOHASH")
	for _, t := range torrents {
		ts := t.Stats()
		done, size := "metadata…", "?"
		if t.Info() != nil {
			done = fmt.Sprintf("%.1f%%", 100*float64(t.BytesCompleted())/float64(max(t.Length(), 1)))
			size = human(float64(t.Length()))
		}
		r := rates[t.InfoHash()]
		fmt.Fprintf(tw, "%s\t%s\t%s\t%s\t%s\t%d/%d\t%d\t%s\n", t.Name(), done, size, human(r.down), human(r.up),
			ts.ActivePeers, ts.TotalPeers, ts.ConnectedSeeders, t.InfoHash().HexString())
	}
	tw.Flush()
	fmt.Fprintln(w, "\nPOST a magnet URI or .torrent file to /add, or an infohash to /remove (?files=delete to delete its data).")
	fmt.Fprintln(w, "anacrolix's own status dump is at /status.")
}

func human(b float64) string {
	const unit = 1024
	if b < unit {
		return fmt.Sprintf("%.0f B", b)
	}
	div, exp := float64(unit), 0
	for n := b / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %ciB", b/div, "KMGTPE"[exp])
}

func writeFileAtomic(path string, b []byte) error {
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, b, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

// collector reads the client's counters at scrape time.
type collector struct{ d *daemon }

var (
	descTorrents  = prometheus.NewDesc("anacrolix_torrents", "Torrents in the client.", nil, nil)
	descPort      = prometheus.NewDesc("anacrolix_listen_port", "Peer port forwarded by NAT-PMP.", nil, nil)
	descPeers     = prometheus.NewDesc("anacrolix_peers", "Peers across all torrents.", []string{"state"}, nil)
	torrentLabels = []string{"infohash", "name"}
	descDown      = prometheus.NewDesc("anacrolix_torrent_downloaded_bytes_total", "Useful payload bytes received.", torrentLabels, nil)
	descUp        = prometheus.NewDesc("anacrolix_torrent_uploaded_bytes_total", "Payload bytes sent.", torrentLabels, nil)
	descDone      = prometheus.NewDesc("anacrolix_torrent_completed_bytes", "Verified bytes on disk.", torrentLabels, nil)
	descSize      = prometheus.NewDesc("anacrolix_torrent_size_bytes", "Total size of the selected files.", torrentLabels, nil)
	descTPeers    = prometheus.NewDesc("anacrolix_torrent_active_peers", "Connected peers.", torrentLabels, nil)
)

func (collector) Describe(ch chan<- *prometheus.Desc) {
	for _, desc := range []*prometheus.Desc{descTorrents, descPort, descPeers, descDown, descUp, descDone, descSize, descTPeers} {
		ch <- desc
	}
}

func (c collector) Collect(ch chan<- prometheus.Metric) {
	torrents := c.d.cl.Torrents()
	st := c.d.cl.Stats()
	ch <- prometheus.MustNewConstMetric(descTorrents, prometheus.GaugeValue, float64(len(torrents)))
	ch <- prometheus.MustNewConstMetric(descPort, prometheus.GaugeValue, float64(c.d.port))
	for state, n := range map[string]int{"active": st.ActivePeers, "known": st.TotalPeers, "half_open": st.HalfOpenPeers, "seeders": st.ConnectedSeeders} {
		ch <- prometheus.MustNewConstMetric(descPeers, prometheus.GaugeValue, float64(n), state)
	}
	for _, t := range torrents {
		ts := t.Stats()
		l := []string{t.InfoHash().HexString(), t.Name()}
		ch <- prometheus.MustNewConstMetric(descDown, prometheus.CounterValue, float64(ts.BytesReadUsefulData.Int64()), l...)
		ch <- prometheus.MustNewConstMetric(descUp, prometheus.CounterValue, float64(ts.BytesWrittenData.Int64()), l...)
		ch <- prometheus.MustNewConstMetric(descTPeers, prometheus.GaugeValue, float64(ts.ActivePeers), l...)
		if t.Info() != nil {
			ch <- prometheus.MustNewConstMetric(descDone, prometheus.GaugeValue, float64(t.BytesCompleted()), l...)
			ch <- prometheus.MustNewConstMetric(descSize, prometheus.GaugeValue, float64(t.Length()), l...)
		}
	}
}
