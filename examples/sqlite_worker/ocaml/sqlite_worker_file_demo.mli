(** Bounded, cancellable Eio file demonstration. *)

type progress =
  { completed_bytes : int
  ; total_bytes : int
  }

type read_result =
  { total_bytes : int
  ; checksum : int64
  }

val file_name : string
val chunk_size : int
val max_file_size : int

val write
  :  sw:Eio.Switch.t
  -> directory:Worker.data_dir
  -> request_id:Bonsai_swiftui_spec.Id.Worker.request_id
  -> total_bytes:int
  -> progress:(progress -> unit)
  -> (unit, string) result

val read
  :  sw:Eio.Switch.t
  -> directory:Worker.data_dir
  -> progress:(progress -> unit)
  -> (read_result, string) result

module For_testing : sig
  val write_chunks
    :  _ Eio.Flow.sink
    -> total_bytes:int
    -> progress:(progress -> unit)
    -> unit

  val read_chunks
    :  _ Eio.Flow.source
    -> declared_total:int
    -> progress:(progress -> unit)
    -> read_result

  val write
    :  after_chunk:(int -> unit)
    -> sw:Eio.Switch.t
    -> directory:Worker.data_dir
    -> request_id:Bonsai_swiftui_spec.Id.Worker.request_id
    -> total_bytes:int
    -> progress:(progress -> unit)
    -> (unit, string) result
end
