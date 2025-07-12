
resource "cloudflare_zero_trust_access_application" "terraform_managed_resource_0fa40737-713b-4314-8d8e-03c6840bfbbc_0" {
  allowed_idps               = []
  app_launcher_visible       = true
  auto_redirect_to_identity  = false
  domain                     = "auth.hogwarts.zone"
  enable_binding_cookie      = false
  http_only_cookie_attribute = false
  name                       = "Pocket ID"
  options_preflight_bypass   = false
  session_duration           = "730h"
  tags                       = []
  type                       = "self_hosted"
  zone_id                    = "ca58567bdcaebb2f5502f8522849fb0b"
  destinations = [{
    type = "public"
    uri  = "auth.hogwarts.zone"
  }]
  policies = [{
    decision   = "bypass"
    exclude    = []
    id         = "48fc9903-b28d-4f95-aff9-03c13b4198f7"
    include = [{
      everyone = {}
    }]
    name             = "Bypass static"
    precedence       = 1
    require          = []
    reusable         = true
    session_duration = "24h"
    uid              = "48fc9903-b28d-4f95-aff9-03c13b4198f7"
  }]
}

resource "cloudflare_zero_trust_access_application" "terraform_managed_resource_284e2229-af4c-470a-84e3-0f261f2b7ce8_1" {
  allowed_idps               = []
  app_launcher_visible       = true
  auto_redirect_to_identity  = false
  domain                     = "ai.hogwarts.zone/static"
  enable_binding_cookie      = false
  http_only_cookie_attribute = false
  name                       = "Open WebUI Static"
  options_preflight_bypass   = false
  session_duration           = "730h"
  tags                       = []
  type                       = "self_hosted"
  zone_id                    = "ca58567bdcaebb2f5502f8522849fb0b"
  destinations = [{
    type = "public"
    uri  = "ai.hogwarts.zone/static"
  }]
  policies = [{
    decision   = "bypass"
    exclude    = []
    id         = "48fc9903-b28d-4f95-aff9-03c13b4198f7"
    include = [{
      everyone = {}
    }]
    name             = "Bypass static"
    precedence       = 1
    require          = []
    reusable         = true
    session_duration = "24h"
    uid              = "48fc9903-b28d-4f95-aff9-03c13b4198f7"
  }]
}

resource "cloudflare_zero_trust_access_application" "terraform_managed_resource_8fe2db29-2bd2-4069-a4ea-aac0683f316d_2" {
  allowed_idps               = []
  app_launcher_visible       = true
  auto_redirect_to_identity  = false
  domain                     = "ombi.hogwarts.zone"
  enable_binding_cookie      = false
  http_only_cookie_attribute = true
  name                       = "Ombi"
  options_preflight_bypass   = false
  session_duration           = "730h"
  tags                       = []
  type                       = "self_hosted"
  zone_id                    = "ca58567bdcaebb2f5502f8522849fb0b"
  destinations = [{
    type = "public"
    uri  = "ombi.hogwarts.zone"
  }]
  policies = [{
    decision   = "allow"
    exclude    = []
    id         = "a0e7ccae-9578-4d71-a21f-6f88139ac704"
    include = [{
      group = {
        id = "729f3c14-5f8e-4050-b3af-6a4f06c4162f"
      }
    }]
    name       = "Default"
    precedence = 2
    require    = []
    reusable   = false
    uid        = "a0e7ccae-9578-4d71-a21f-6f88139ac704"
  }]
}

resource "cloudflare_zero_trust_access_application" "terraform_managed_resource_c600b60c-7c0a-4a77-af98-3c7109a6b78b_3" {
  allowed_idps               = []
  app_launcher_visible       = false
  auto_redirect_to_identity  = false
  domain                     = "minio.hogwarts.zone"
  enable_binding_cookie      = false
  http_only_cookie_attribute = true
  name                       = "Minio"
  options_preflight_bypass   = true
  session_duration           = "730h"
  tags                       = []
  type                       = "self_hosted"
  zone_id                    = "ca58567bdcaebb2f5502f8522849fb0b"
  destinations = [{
    type = "public"
    uri  = "minio.hogwarts.zone"
  }]
  policies = [{
    decision   = "bypass"
    exclude    = []
    id         = "a8c3efb1-712f-44a4-857b-dd28662568bc"
    include = [{
      everyone = {}
    }]
    name       = "Default"
    precedence = 1
    require    = []
    reusable   = false
    uid        = "a8c3efb1-712f-44a4-857b-dd28662568bc"
  }]
}

resource "cloudflare_zero_trust_access_application" "terraform_managed_resource_dda7646e-aee4-4737-af47-66b8ffdc25b9_4" {
  allowed_idps               = []
  app_launcher_visible       = true
  auto_redirect_to_identity  = false
  domain                     = "pve.hogwarts.zone"
  enable_binding_cookie      = false
  http_only_cookie_attribute = true
  name                       = "Proxmox"
  options_preflight_bypass   = false
  session_duration           = "730h"
  tags                       = []
  type                       = "self_hosted"
  zone_id                    = "ca58567bdcaebb2f5502f8522849fb0b"
  destinations = [{
    type = "public"
    uri  = "pve.hogwarts.zone"
  }]
  policies = [{
    decision   = "allow"
    exclude    = []
    id         = "1e8b9663-0b4f-426e-a166-5a43e3b17a28"
    include = [{
      group = {
        id = "d3a2897e-7d45-41dc-a3ae-3d22bcddd24a"
      }
    }]
    name       = "pve"
    precedence = 1
    require    = []
    reusable   = false
    uid        = "1e8b9663-0b4f-426e-a166-5a43e3b17a28"
  }]
}

resource "cloudflare_zero_trust_access_application" "terraform_managed_resource_59ae7808-320d-40c0-8101-ac69aee86c48_5" {
  allowed_idps               = []
  app_launcher_visible       = true
  auto_redirect_to_identity  = false
  domain                     = "fr24.hogwarts.zone"
  enable_binding_cookie      = false
  http_only_cookie_attribute = true
  name                       = "fr24"
  options_preflight_bypass   = false
  session_duration           = "730h"
  tags                       = []
  type                       = "self_hosted"
  zone_id                    = "ca58567bdcaebb2f5502f8522849fb0b"
  destinations = [{
    type = "public"
    uri  = "fr24.hogwarts.zone"
  }]
  policies = [{
    decision   = "allow"
    exclude    = []
    id         = "fd138dcb-a978-4491-993b-97caf946060e"
    include = [{
      group = {
        id = "d3a2897e-7d45-41dc-a3ae-3d22bcddd24a"
      }
    }]
    name       = "Default"
    precedence = 1
    require    = []
    reusable   = false
    uid        = "fd138dcb-a978-4491-993b-97caf946060e"
  }]
}

resource "cloudflare_zero_trust_access_application" "terraform_managed_resource_ca367972-55e3-41ce-a10c-28b1728c2f99_6" {
  allowed_idps               = []
  app_launcher_visible       = true
  auto_redirect_to_identity  = false
  domain                     = "ai.hogwarts.zone"
  enable_binding_cookie      = false
  http_only_cookie_attribute = true
  name                       = "Open WebUI"
  options_preflight_bypass   = false
  session_duration           = "730h"
  tags                       = []
  type                       = "self_hosted"
  zone_id                    = "ca58567bdcaebb2f5502f8522849fb0b"
  destinations = [{
    type = "public"
    uri  = "ai.hogwarts.zone"
  }]
  policies = [{
    decision   = "allow"
    exclude    = []
    id         = "5247fde1-0e9b-4af4-aadb-01db560a08b9"
    include = [{
      group = {
        id = "d3a2897e-7d45-41dc-a3ae-3d22bcddd24a"
      }
    }]
    name       = "default"
    precedence = 1
    require    = []
    reusable   = false
    uid        = "5247fde1-0e9b-4af4-aadb-01db560a08b9"
  }]
}

resource "cloudflare_zero_trust_access_application" "terraform_managed_resource_53b0abfc-053b-4e17-aca4-0c4e7aab4d6a_7" {
  allowed_idps               = []
  app_launcher_visible       = true
  auto_redirect_to_identity  = false
  domain                     = "transmission.hogwarts.zone"
  enable_binding_cookie      = false
  http_only_cookie_attribute = true
  name                       = "Transmission"
  options_preflight_bypass   = false
  session_duration           = "730h"
  tags                       = []
  type                       = "self_hosted"
  zone_id                    = "ca58567bdcaebb2f5502f8522849fb0b"
  destinations = [{
    type = "public"
    uri  = "transmission.hogwarts.zone"
  }]
  policies = [{
    decision   = "allow"
    exclude    = []
    id         = "938e5e42-6995-45f0-8f09-086cd658b851"
    include = [{
      group = {
        id = "d3a2897e-7d45-41dc-a3ae-3d22bcddd24a"
      }
    }]
    name             = "transmission"
    precedence       = 1
    require          = []
    reusable         = false
    session_duration = "730h"
    uid              = "938e5e42-6995-45f0-8f09-086cd658b851"
  }]
}

resource "cloudflare_zero_trust_access_application" "terraform_managed_resource_9106e22d-dc04-4961-aa1c-65b62ef9240e_8" {
  allowed_idps               = []
  app_launcher_visible       = true
  auto_redirect_to_identity  = false
  domain                     = "portainer.hogwarts.zone"
  enable_binding_cookie      = false
  http_only_cookie_attribute = true
  name                       = "Portainer"
  options_preflight_bypass   = false
  session_duration           = "730h"
  tags                       = []
  type                       = "self_hosted"
  zone_id                    = "ca58567bdcaebb2f5502f8522849fb0b"
  destinations = [{
    type = "public"
    uri  = "portainer.hogwarts.zone"
  }]
  policies = [{
    decision   = "allow"
    exclude    = []
    id         = "cdeb28aa-66d6-4916-9935-94e9c1fcc77f"
    include = [{
      group = {
        id = "d3a2897e-7d45-41dc-a3ae-3d22bcddd24a"
      }
    }]
    name       = "Portainer"
    precedence = 1
    require    = []
    reusable   = false
    uid        = "cdeb28aa-66d6-4916-9935-94e9c1fcc77f"
  }]
}

resource "cloudflare_zero_trust_access_application" "terraform_managed_resource_129b76aa-7ec6-40e1-b5c0-92bdf9ddc9c3_9" {
  allowed_idps               = []
  app_launcher_visible       = true
  auto_redirect_to_identity  = false
  domain                     = "sonarr.hogwarts.zone"
  enable_binding_cookie      = false
  http_only_cookie_attribute = true
  name                       = "Sonarr"
  options_preflight_bypass   = false
  session_duration           = "730h"
  tags                       = []
  type                       = "self_hosted"
  zone_id                    = "ca58567bdcaebb2f5502f8522849fb0b"
  destinations = [{
    type = "public"
    uri  = "sonarr.hogwarts.zone"
  }]
  policies = [{
    decision   = "allow"
    exclude    = []
    id         = "11ad9159-77a3-4bcb-9a9f-0d143bb3132f"
    include = [{
      group = {
        id = "d3a2897e-7d45-41dc-a3ae-3d22bcddd24a"
      }
    }]
    name       = "Sonarr"
    precedence = 1
    require    = []
    reusable   = false
    uid        = "11ad9159-77a3-4bcb-9a9f-0d143bb3132f"
  }]
}

resource "cloudflare_zero_trust_access_application" "terraform_managed_resource_6b1ecbdc-6c79-4827-b49c-b4d02180dc13_10" {
  allowed_idps               = []
  app_launcher_visible       = true
  auto_redirect_to_identity  = false
  domain                     = "prowlarr.hogwarts.zone"
  enable_binding_cookie      = false
  http_only_cookie_attribute = true
  name                       = "Prowlarr"
  options_preflight_bypass   = false
  session_duration           = "730h"
  tags                       = []
  type                       = "self_hosted"
  zone_id                    = "ca58567bdcaebb2f5502f8522849fb0b"
  destinations = [{
    type = "public"
    uri  = "prowlarr.hogwarts.zone"
  }]
  policies = [{
    decision   = "allow"
    exclude    = []
    id         = "bbe186ed-5c27-4ec1-a471-20208737a2f3"
    include = [{
      group = {
        id = "d3a2897e-7d45-41dc-a3ae-3d22bcddd24a"
      }
    }]
    name       = "prowlarr"
    precedence = 1
    require    = []
    reusable   = false
    uid        = "bbe186ed-5c27-4ec1-a471-20208737a2f3"
  }]
}

resource "cloudflare_zero_trust_access_application" "terraform_managed_resource_e921e0ad-8511-466f-b621-6a924461c859_11" {
  allowed_idps               = []
  app_launcher_visible       = true
  auto_redirect_to_identity  = false
  domain                     = "radarr.hogwarts.zone"
  enable_binding_cookie      = false
  http_only_cookie_attribute = true
  name                       = "Radarr"
  options_preflight_bypass   = false
  session_duration           = "730h"
  tags                       = []
  type                       = "self_hosted"
  zone_id                    = "ca58567bdcaebb2f5502f8522849fb0b"
  destinations = [{
    type = "public"
    uri  = "radarr.hogwarts.zone"
  }]
  policies = [{
    decision   = "allow"
    exclude    = []
    id         = "d0a48de1-e96e-4901-a699-a6054839fe5d"
    include = [{
      group = {
        id = "d3a2897e-7d45-41dc-a3ae-3d22bcddd24a"
      }
    }]
    name       = "Default"
    precedence = 1
    require    = []
    reusable   = false
    uid        = "d0a48de1-e96e-4901-a699-a6054839fe5d"
  }]
}
