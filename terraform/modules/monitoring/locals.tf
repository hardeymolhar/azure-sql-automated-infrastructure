locals {
  client_ip = chomp(data.http.client_ip.response_body)
}