defmodule Bandit.HTTP2.Frame.PushPromise do
  @moduledoc false

  import Bandit.HTTP2.Frame.Flags

  alias Bandit.HTTP2.{Connection, Errors, Frame, Stream}

  defstruct stream_id: nil,
            end_headers: false,
            promised_stream_id: nil,
            fragment: nil

  @typedoc "An HTTP/2 PUSH_PROMISE frame"
  @type t :: %__MODULE__{
          stream_id: Stream.stream_id(),
          end_headers: boolean(),
          promised_stream_id: Stream.stream_id(),
          fragment: iodata()
        }

  @end_headers_bit 2
  @padding_bit 3

  @spec deserialize(Frame.flags(), Stream.stream_id(), iodata()) ::
          {:ok, t()} | {:error, Connection.error()}
  def deserialize(_flags, 0, _payload) do
    {:error,
     {:connection, Errors.protocol_error(),
      "PUSH_PROMISE frame with zero stream_id (RFC7540§6.6)"}}
  end

  def deserialize(
        flags,
        stream_id,
        <<padding_length::8, 0::1, promised_stream_id::31, rest::binary>>
      )
      when set?(flags, @padding_bit) and byte_size(rest) >= padding_length do
    {:ok,
     %__MODULE__{
       stream_id: stream_id,
       end_headers: set?(flags, @end_headers_bit),
       promised_stream_id: promised_stream_id,
       fragment: binary_part(rest, 0, byte_size(rest) - padding_length)
     }}
  end

  def deserialize(flags, stream_id, <<0::1, promised_stream_id::31, fragment::binary>>)
      when clear?(flags, @padding_bit) do
    {:ok,
     %__MODULE__{
       stream_id: stream_id,
       end_headers: set?(flags, @end_headers_bit),
       promised_stream_id: promised_stream_id,
       fragment: fragment
     }}
  end

  def deserialize(
        flags,
        _stream_id,
        <<_padding_length::8, _reserved::1, _promised_stream_id::31, _rest::binary>>
      )
      when set?(flags, @padding_bit) do
    {:error,
     {:connection, Errors.protocol_error(),
      "PUSH_PROMISE frame with invalid padding length (RFC7540§6.6)"}}
  end

  defimpl Frame.Serializable do
    alias Bandit.HTTP2.Frame.{Continuation, PushPromise}

    @end_headers_bit 2

    def serialize(%PushPromise{} = frame, max_frame_size) do
      fragment_length = IO.iodata_length(frame.fragment)
      max_fragment_size = max_frame_size - 4

      if fragment_length <= max_fragment_size do
        [
          {0x5, set([@end_headers_bit]), frame.stream_id,
           [<<frame.promised_stream_id::32>>, frame.fragment]}
        ]
      else
        <<this_frame::binary-size(max_fragment_size), rest::binary>> =
          IO.iodata_to_binary(frame.fragment)

        [
          {0x5, 0x00, frame.stream_id, <<frame.promised_stream_id::32, this_frame::binary>>}
          | Frame.Serializable.serialize(
              %Continuation{
                stream_id: frame.stream_id,
                fragment: rest
              },
              max_frame_size
            )
        ]
      end
    end
  end
end
