defmodule Sippet.MessageOrdering do
  @moduledoc """
  Provides functions to ensure Content-Length header appears last in SIP messages
  while maintaining full compatibility with Sippet's existing API.

  This module provides drop-in replacements for common Sippet.Message functions
  that guarantee proper header ordering during serialization.

  ## Usage in your existing code

      # Instead of: Message.to_string(message)
      message_string = MessageOrdering.to_string(message)

      # Instead of: to_string(message)
      message_string = MessageOrdering.to_string(message)

      # All other Sippet functions work normally
      response = Message.to_response(request, 200)
      response_string = MessageOrdering.to_string(response)

  ## Integration with transactions and transport

  This module works seamlessly with Sippet's transaction and transport layers.
  Just use MessageOrdering.to_string/1 instead of the standard to_string/1
  when you need guaranteed header ordering.
  """

  alias Sippet.Message
  alias Sippet.Message.RequestLine
  alias Sippet.Message.StatusLine

  @doc """
  Converts a Sippet.Message to string with Content-Length as the last header.

  This is a drop-in replacement for `Sippet.Message.to_string/1` that ensures
  the Content-Length header appears as the final header before the message body.

  ## Examples

      iex> request = Message.build_request(:invite, "sip:user@example.com")
      iex> request = Message.put_header(request, :via, via_header)
      iex> MessageOrdering.to_string(request)
      "INVITE sip:user@example.com SIP/2.0\\r\\nVia: ...\\r\\nContent-Length: 0\\r\\n\\r\\n"
  """
  @spec to_string(Message.t()) :: String.t()
  def to_string(%Message{} = message) do
    message |> to_iodata() |> IO.iodata_to_binary()
  end

  @doc """
  Converts a Sippet.Message to iodata with Content-Length as the last header.

  This is useful when you need better performance for network operations,
  as iodata can be sent directly to sockets without conversion to binary.

  ## Examples

      # For better performance when sending over network
      iodata = MessageOrdering.to_iodata(message)
      :gen_tcp.send(socket, iodata)
  """
  @spec to_iodata(Message.t()) :: iodata()
  def to_iodata(%Message{} = message) do
    start_line =
      case message.start_line do
        %RequestLine{} -> RequestLine.to_iodata(message.start_line)
        %StatusLine{} -> StatusLine.to_iodata(message.start_line)
      end

    # Ensure Content-Length header is present
    message_with_content_length =
      if Map.has_key?(message.headers, :content_length) do
        message
      else
        len = if message.body == nil, do: 0, else: String.length(message.body)
        %{message | headers: Map.put(message.headers, :content_length, len)}
      end

    [
      start_line,
      "\r\n",
      format_headers_with_content_length_last(message_with_content_length.headers),
      "\r\n",
      if(message_with_content_length.body == nil, do: "", else: message_with_content_length.body)
    ]
  end

  @doc """
  Replaces Sippet's default String.Chars implementation globally.

  **WARNING**: This modifies global behavior. Only use this if you want
  ALL Sippet messages in your application to have Content-Length last.

  Call this function once during application startup.

  ## Example

      # In your application startup code
      def start(_type, _args) do
        Sippet.MessageOrdering.replace_default_string_conversion()
        # ... rest of your startup code
      end
  """
  def replace_default_string_conversion do
    # This will replace the existing String.Chars implementation
    defimpl String.Chars, for: Sippet.Message do
      def to_string(%Sippet.Message{} = message) do
        Sippet.MessageOrdering.to_string(message)
      end
    end
  end

  ## Private implementation

  defp format_headers_with_content_length_last(headers) do
    # Separate Content-Length from other headers
    {content_length, other_headers} = Map.pop(headers, :content_length)

    # Format other headers first
    other_headers_iodata =
      other_headers
      |> Map.to_list()
      |> Enum.map(fn {name, value} -> format_header(name, value) end)

    # Format Content-Length last (if present)
    content_length_iodata =
      if content_length != nil do
        [format_header(:content_length, content_length)]
      else
        []
      end

    # Combine with Content-Length at the end
    other_headers_iodata ++ content_length_iodata
  end

  defp format_header(name, value) do
    {header_name, multiple} = get_header_name_and_type(name)

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

  # Header name and type mapping (based on Sippet.Message internals)
  defp get_header_name_and_type(name) do
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
      other when is_atom(other) -> {format_atom_header_name(other), false}
      other when is_binary(other) -> {other, false}
    end
  end

  defp format_atom_header_name(atom) do
    atom
    |> to_string()
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join("-")
  end

  # Header value formatting (mirrors Sippet.Message internal logic)
  defp format_header_value(value) when is_binary(value), do: value
  defp format_header_value(value) when is_integer(value), do: Integer.to_string(value)

  # CSeq header: {sequence, method}
  defp format_header_value({sequence, method}) when is_integer(sequence) do
    method_str = format_method(method)
    [Integer.to_string(sequence), " ", method_str]
  end

  # Via header: {{major, minor}, protocol, {host, port}, params}
  defp format_header_value({{major, minor}, protocol, {host, port}, %{} = parameters})
       when is_integer(major) and is_integer(minor) and
            is_binary(host) and is_integer(port) do
    protocol_str = format_protocol(protocol)
    [
      "SIP/",
      Integer.to_string(major),
      ".",
      Integer.to_string(minor),
      "/",
      protocol_str,
      " ",
      host,
      if(port > 0, do: [":", Integer.to_string(port)], else: ""),
      format_parameters(parameters)
    ]
  end

  # URI headers with display name: {display_name, uri, params}
  defp format_header_value({display_name, %Sippet.URI{} = uri, %{} = parameters}) do
    display_part = if display_name != "", do: [display_name, " "], else: ""
    [display_part, "<", Sippet.URI.to_string(uri), ">", format_parameters(parameters)]
  end

  # Content-Type header: {{type, subtype}, params}
  defp format_header_value({{type, subtype}, %{} = parameters})
       when is_binary(type) and is_binary(subtype) do
    [type, "/", subtype, format_parameters(parameters)]
  end

  # Token with parameters: {token, params}
  defp format_header_value({token, %{} = parameters}) when is_binary(token) do
    [token, format_parameters(parameters)]
  end

  # Auth headers: {scheme, params}
  defp format_header_value({scheme, %{} = parameters}) when is_binary(scheme) do
    [scheme, format_parameters(parameters)]
  end

  # Lists of values
  defp format_header_value(values) when is_list(values) do
    values
    |> Enum.map(&format_header_value/1)
    |> Enum.join(", ")
  end

  # Fallback
  defp format_header_value(value), do: to_string(value)

  defp format_method(method) when is_atom(method) do
    method |> to_string() |> String.upcase()
  end
  defp format_method(method) when is_binary(method), do: String.upcase(method)

  defp format_protocol(protocol) when is_atom(protocol) do
    protocol |> to_string() |> String.upcase()
  end
  defp format_protocol(protocol) when is_binary(protocol), do: String.upcase(protocol)

  defp format_parameters(%{} = parameters) when map_size(parameters) == 0, do: ""
  defp format_parameters(%{} = parameters) do
    parameters
    |> Enum.map(fn {name, value} ->
      if value == "" do
        [";", name]
      else
        [";", name, "=", quote_parameter_value_if_needed(value)]
      end
    end)
  end

  defp quote_parameter_value_if_needed(value) when is_binary(value) do
    # Quote if the value contains spaces, commas, semicolons, or equals
    if String.contains?(value, [" ", ",", ";", "=", "\""]) do
      # Escape existing quotes and wrap in quotes
      escaped_value = String.replace(value, "\"", "\\\"")
      ["\"", escaped_value, "\""]
    else
      value
    end
  end
  defp quote_parameter_value_if_needed(value), do: to_string(value)
end
