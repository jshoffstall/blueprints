job "api" {
    datacenters = ["onprem"]
    region = "onprem"
    type = "service"

    group "api" {
        count = 1

        network {
            mode = "bridge"

            // port "http" {
            //     to = "9090"
            // }

            // port "statsd" {
            //     to = "9125"
            // }

            port "prometheus" {
                to = "9102"
            }
        }

        service {
            name = "exporter"
            port = "prometheus"

            connect {
                sidecar_service {}
            }
        }

        task "exporter" {
            driver = "docker"

            config {
                image = "prom/statsd-exporter"
            }

            resources {
                cpu    = 50
                memory = 64
            }

            lifecycle {
                hook = "prestart"
                sidecar = true
            }
        }

        task "service-defaults" {
            driver = "docker"

            template {
                destination   = "local/central-config.sh"
                data = <<EOH
consul config write - <<EOF
kind = "service-defaults"
name = "api"
protocol="http"
EOF
EOH
            }

            lifecycle {
                hook = "prestart"
            }

            config {
                image = "consul:1.7.2"
                command = "sh"
                args = ["/central-config.sh"]
                volumes = ["local/central-config.sh:/central-config.sh"]
            }

            env {
                CONSUL_HTTP_ADDR="${attr.unique.network.ip-address}:8500"
            }
        }

        service {
            name = "api"
            port = "9090"

            connect {
                sidecar_service {
                    proxy {
                        config {
                            envoy_dogstatsd_url = "udp://127.0.0.1:9125"
                            envoy_stats_tags = ["datacenter=onprem"]
                        }
                        
                        upstreams {
                            destination_name = "database"
                            local_bind_port = 5432
                        }
                    }
                }
            }
        }

        task "api" {
            driver = "docker"

            config {
                image = "nicholasjackson/fake-service:v0.9.0"
            }

            env {
                NAME = "api-onprem"
                MESSAGE = "ok"
                LISTEN_ADDR = "0.0.0.0:9090"
                UPSTREAM_URIS = "http://localhost:5432"
                TIMING_VARIANCE = "25"
                HTTP_CLIENT_KEEP_ALIVES = "true"
            }

            resources {
                cpu    = 100
                memory = 256
            }
        }
    }
}
