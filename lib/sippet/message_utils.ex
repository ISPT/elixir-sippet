defmodule Sippet.MessageUtils do
  @moduledoc """
  Utilities for manipulating SIP messages, including header ordering control.
  """

  alias Sippet.Message
  alias Sippet.Message.RequestLine
  alias Sippet.Message.StatusLine

  @doc """
  Converts a message to string with Content-Length header as the last header.

  This function ensures that the Content-Length header appears as the final
  header before the message body, which can be useful for certain SIP
  implementations that expect this ordering.

  ## Examples

      iex> message = Message.build_request(:invite, "sip:user@example.com")
      iex> message = Message.put_header(message, :via, {{2, 0}, :udp, {"proxy.com", 5060}, %{"branch" => "z9hG4bK123"}})
      iex> message = Message.put_header(message, :from, {"Alice", URI.parse("sip:alice@example.com"), %{"tag" => "abc123"}})
      iex> MessageUtils.to_string_with_content_length_last(message)
      "INVITE sip:user@example.com SIP/2.0\\r\\n..."

  """
  @spec to_string_with_content_length_last(Message.t()) :: String.t()
  def to_string_with_content_length_last(%Message{} = message) do
    # Ensure Content-Length is set
    message = ensure_content_length(message)

    # Build the message with ordered headers
    start_line = format_start_line(message.start_line)
    headers_iodata = format_headers_with_content_length_last(message.headers)
    body = if message.body == nil, do: "", else: message.body

    [start_line, "\r\n", headers_iodata, "\r\n", body]
    |> IO.iodata_to_binary()
  end

  @doc """
  Converts a message to iodata with Content-Length header as the last header.

  Similar to `to_string_with_content_length_last/1` but returns iodata for
  better performance when the result will be written to a socket or file.
  """
  @spec to_iodata_with_content_length_last(Message.t()) :: iodata()
  def to_iodata_with_content_length_last(%Message{} = message) do
    # Ensure Content-Length is set
    message = ensure_content_length(message)

    # Build the message with ordered headers
    start_line = format_start_line(message.start_line)
    headers_iodata = format_headers_with_content_length_last(message.headers)
    body = if message.body == nil, do: "", else: message.body

    [start_line, "\r\n", headers_iodata, "\r\n", body]
  end

  @doc """
  Reorders headers in a message so that Content-Length appears last.

  Returns a new message with the same content but with headers reordered.
  This is useful if you need to maintain the Message struct but want to
  control the serialization order.

  Note: This creates a new headers map with a specific insertion order,
  but the order is only guaranteed when using the custom formatting
  functions in this module.
  """
  @spec reorder_headers_for_content_length_last(Message.t()) :: Message.t()
  def reorder_headers_for_content_length_last(%Message{} = message) do
    # Ensure Content-Length is set
    message = ensure_content_length(message)

    # Extract content_length and other headers
    {content_length, other_headers} = Map.pop(message.headers, :content_length)

    # Rebuild headers map with content_length last
    # Note: This order is only guaranteed with custom formatting functions
    reordered_headers =
      other_headers
      |> Map.put(:content_length, content_length)

    %{message | headers: reordered_headers}
  end

  # Private helper functions

  defp ensure_content_length(%Message{headers: headers, body: body} = message) do
    if Map.has_key?(headers, :content_length) do
      message
    else
      content_length = if body == nil, do: 0, else: String.length(body)
      %{message | headers: Map.put(headers, :content_length, content_length)}
    end
  end

  defp format_start_line(%RequestLine{} = request_line) do
    RequestLine.to_iodata(request_line)
  end

  defp format_start_line(%StatusLine{} = status_line) do
    StatusLine.to_iodata(status_line)
  end

  defp format_headers_with_content_length_last(headers) do
    # Separate Content-Length from other headers
    {content_length, other_headers} = Map.pop(headers, :content_length)

    # Format other headers first
    other_headers_iodata =
      other_headers
      |> Map.to_list()
      |> Enum.map(fn {name, value} -> format_single_header(name, value) end)

    # Format Content-Length last
    content_length_iodata =
      if content_length != nil do
        [format_single_header(:content_length, content_length)]
      else
        []
      end

    # Combine all headers with Content-Length at the end
    other_headers_iodata ++ content_length_iodata
  end

  defp format_single_header(name, value) do
    # Use the same logic as the original Message module
    {header_name, multiple} = get_header_info(name)

    formatted_value =
      if multiple && is_list(value) do
        value
        |> Enum.map(&format_header_value/1)
        |> Enum.join(", ")
      else
        format_header_value(value)
      end

    [header_name, ": ", formatted_value, "\r\n"]
  end

  defp get_header_info(name) do
    case name do
      :accept -> {"Accept", true}
      :accept_encoding -> {"Accept-Encoding", true}
      :accept_language -> {"Accept-Language", true}
      :alert_info -> {"Alert-Info", true}
      :allow -> {"Allow", true}
      :authentication_info -> {"Authentication-Info", false}
      :authorization -> {"Authorization", false}
      :call_id -> {"Call-ID", true}
      :call_info -> {"Call-Info", true}
      :contact -> {"Contact", true}
      :content_disposition -> {"Content-Disposition", true}
      :content_encoding -> {"Content-Encoding", true}
      :content_language -> {"Content-Language", true}
      :content_length -> {"Content-Length", true}
      :content_type -> {"Content-Type", true}
      :cseq -> {"CSeq", true}
      :date -> {"Date", true}
      :error_info -> {"Error-Info", true}
      :expires -> {"Expires", true}
      :from -> {"From", true}
      :in_reply_to -> {"In-Reply-To", true}
      :max_forwards -> {"Max-Forwards", true}
      :min_expires -> {"Min-Expires", true}
      :mime_version -> {"MIME-Version", true}
      :organization -> {"Organization", true}
      :priority -> {"Priority", true}
      :proxy_authenticate -> {"Proxy-Authenticate", true}
      :proxy_authorization -> {"Proxy-Authorization", false}
      :proxy_require -> {"Proxy-Require", true}
      :record_route -> {"Record-Route", true}
      :reply_to -> {"Reply-To", true}
      :require -> {"Require", true}
      :retry_after -> {"Retry-After", true}
      :route -> {"Route", true}
      :server -> {"Server", true}
      :subject -> {"Subject", true}
      :supported -> {"Supported", true}
      :timestamp -> {"Timestamp", true}
      :to -> {"To", true}
      :unsupported -> {"Unsupported", true}
      :user_agent -> {"User-Agent", true}
      :via -> {"Via", true}
      :warning -> {"Warning", true}
      :www_authenticate -> {"WWW-Authenticate", true}
      other when is_atom(other) -> {other |> to_string() |> header_case(), false}
      other when is_binary(other) -> {header_case(other), false}
    end
  end

  defp header_case(header) when is_binary(header) do
    header
    |> String.split("-")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join("-")
  end

  defp format_header_value(value) when is_binary(value), do: value
  defp format_header_value(value) when is_integer(value), do: Integer.to_string(value)

  defp format_header_value({sequence, method}) when is_integer(sequence) do
    method_str = if is_atom(method), do: method |> to_string() |> String.upcase(), else: method
    [Integer.to_string(sequence), " ", method_str]
  end

  defp format_header_value({token, %{} = parameters}) when is_binary(token) do
    [token, format_parameters(parameters)]
  end

  defp format_header_value({{type, subtype}, %{} = parameters})
       when is_binary(type) and is_binary(subtype) do
    [type, "/", subtype, format_parameters(parameters)]
  end

  defp format_header_value({{major, minor}, protocol, {host, port}, %{} = parameters})
       when is_integer(major) and is_integer(minor) and
            is_binary(host) and is_integer(port) do
    protocol_str = if is_atom(protocol), do: protocol |> to_string() |> String.upcase(), else: protocol
    port_str = if port > 0, do: [":", Integer.to_string(port)], else: ""
    [
      "SIP/",
      Integer.to_string(major),
      ".",
      Integer.to_string(minor),
      "/",
      protocol_str,
      " ",
      host,
      port_str,
      format_parameters(parameters)
    ]
  end

  defp format_header_value({display_name, %URI{} = uri, %{} = parameters}) do
    display_part = if display_name != "", do: [display_name, " "], else: ""
    [display_part, "<", URI.to_string(uri), ">", format_parameters(parameters)]
  end

  defp format_header_value({scheme, %{} = parameters}) when is_binary(scheme) do
    [scheme, format_parameters(parameters)]
  end

  defp format_header_value(value) when is_list(value) do
    value |> Enum.map(&format_header_value/1) |> Enum.join(", ")
  end

  defp format_header_value(value), do: to_string(value)

  defp format_parameters(%{} = parameters) do
    parameters
    |> Enum.map(fn {name, value} ->
      if value == "" do
        [";", name]
      else
        [";", name, "=", maybe_quote_value(value)]
      end
    end)
  end

  defp maybe_quote_value(value) when is_binary(value) do
    # Simple heuristic: quote if contains spaces or special characters
    if String.contains?(value, [" ", ",", ";", "="]) do
      ["\"", value, "\""]
    else
      value
    end
  end

  defp maybe_quote_value(value), do: to_string(value)
end
