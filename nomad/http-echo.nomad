job "http-echo" {
  datacenters = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]

  update {
    max_parallel      = 1
    health_check      = "checks"
    min_healthy_time  = "45s"
    healthy_deadline  = "5m"
    auto_revert       = true
    stagger           = "30s" 
  }

  meta {
    hello = "world"
  }

  group "http-echo" {
    network {
      port "http" {
        static = 8080
      }
    }

    task "http-echo" {
      driver = "docker"

      config {
        image = "sofixa/http-echo:0.2.4-scratch"
        args = ["-text", "Hello, world", "-listen", ":8080"]
        ports = ["http"]
      }

      resources {
        cpu    = 10
        memory = 24
      }

      service {
        name = "http-echo"
        port = "http"
        check {
          type     = "http"
          path     = "/"
          interval = "5s"
          timeout  = "2s"
        }
        tags = ["team-1", "test"]
      }
    }
  }
}
