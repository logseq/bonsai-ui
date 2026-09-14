type trust =
  [ `Nss
  | `Test_certificate
  ]

val tls_handshake
  :  cert_pem:string
  -> key_pem:string
  -> trust:trust
  -> host:string
  -> (unit, string) result

val https_get : cert_pem:string -> key_pem:string -> (string, string) result

val https_cancel_closes_transport
  :  cert_pem:string
  -> key_pem:string
  -> (bool, string) result

val wss_echo : cert_pem:string -> key_pem:string -> string -> (string, string) result

val wss_disconnect_closes_transport
  :  cert_pem:string
  -> key_pem:string
  -> (bool, string) result

val public_https_get
  :  host:string
  -> port:int
  -> resource:string
  -> (string, string) result

val public_wss_echo
  :  host:string
  -> port:int
  -> resource:string
  -> string
  -> (string, string) result
