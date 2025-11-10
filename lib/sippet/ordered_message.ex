defmodule Sippet.OrderedMessage do
  @moduledoc """
  A wrapper around Sippet.Message that ensures Content-Length header appears last
  when the message is converted to string, while maintaining full compatibility
  with Sippet's transaction and transport layers.

  This module provides a transparent wrapper that can be used anywhere a
  Sippet.Message is expected, but guarantees proper header ordering during
  serialization.

  ## Usage

      # Wrap an existing message
      ordered_message = OrderedMessage.new(message)

      # Or build directly
      ordered_message =
        OrderedMessage.build_request(:invite, "sip:user@example.com")
        |> OrderedMessage.put_header(:via, via_header)
        |> OrderedMessage.put_header(:from, from_header)

      # Works with all Sippet functions
      response = Sippet.Message.to_response(ordered_message, 200)
      transaction_key = Sippet.Transactions.Client.Key.new(ordered_message)

      # String conversion ensures Content-Length is last
      message_string = to_string(ordered_message)
  """

  @behaviour Access

  alias Sippet.Message
  alias Sippet.Message.RequestLine
  alias Sippet.Message.StatusLine

  defstruct [:inner_message]

  @type t :: %__MODULE__{inner_message: Message.t()}

  ## Construction

  @doc """
  Creates a new OrderedMessage wrapping the given Sippet.Message.
  """
  @spec new(Message.t()) :: t()
  def new(%Message{} = message) do
    %__MODULE__{inner_message: message}
  end

  @doc """
  Builds a new request message with ordered headers.
  """
  @spec build_request(Message.method(), Message.uri()) :: t()
  def build_request(method, request_uri) do
    Message.build_request(method, request_uri) |> new()
  end

  @doc """
  Builds a new response message with ordered headers.
  """
  @spec build_response(pos_integer(), binary()) :: t()
  def build_response(status_code, reason_phrase \\ nil) do
    Message.build_response(status_code, reason_phrase) |> new()
  end

  ## Header manipulation (delegate to inner message and rewrap)

  @doc """
  Adds or replaces a header in the message.
  """
  @spec put_header(t(), Message.header(), any()) :: t()
  def put_header(%__MODULE__{inner_message: message} = ordered_msg, header, value) do
    new_message = Message.put_header(message, header, value)
    %{ordered_msg | inner_message: new_message}
  end

  @doc """
  Gets a header value from the message.
  """
  @spec get_header(t(), Message.header(), any()) :: any()
  def get_header(%__MODULE__{inner_message: message}, header, default \\ nil) do
    Message.get_header(message, header, default)
  end

  @doc """
  Deletes a header from the message.
  """
  @spec delete_header(t(), Message.header()) :: t()
  def delete_header(%__MODULE__{inner_message: message} = ordered_msg, header) do
    new_message = Message.delete_header(message, header)
    %{ordered_msg | inner_message: new_message}
  end

  @doc """
  Sets the message body.
  """
  @spec put_body(t(), binary() | nil) :: t()
  def put_body(%__MODULE__{inner_message: message} = ordered_msg, body) do
    new_message = Message.put_body(message, body)
    %{ordered_msg | inner_message: new_message}
  end

  ## Access behavior (for compatibility)

  def fetch(%__MODULE__{inner_message: message}, key) do
    Map.fetch(message, key)
  end

  def get_and_update(%__MODULE__{inner_message: message} = ordered_msg, key, fun) do
    case Map.get_and_update(message, key, fun) do
      {get_value, new_message} ->
        {get_value, %{ordered_msg | inner_message: new_message}}
    end
  end

  def pop(%__MODULE__{inner_message: message} = ordered_msg, key, default \\ nil) do
    case Map.pop(message, key, default) do
      {value, new_message} ->
        {value, %{ordered_msg | inner_message: new_message}}
    end
  end

  ## Conversion and serialization with ordered headers

  @doc """
  Converts the OrderedMessage to iodata with Content-Length as the last header.
  """
  @spec to_iodata(t()) :: iodata()
  def to_iodata(%__MODULE__{inner_message: message}) do
    start_line =
      case message.start_line do
        %RequestLine{} -> RequestLine.to_iodata(message.start_line)
        %StatusLine{} -> StatusLine.to_iodata(message.start_line)
      end

    # Ensure Content-Length is present
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
      do_ordered_headers(message_with_content_length.headers),
      "\r\n",
      if(message_with_content_length.body == nil, do: "", else: message_with_content_length.body)
    ]
  end

  @doc """
  Converts the OrderedMessage to binary string with Content-Length as the last header.
  """
  @spec to_binary(t()) :: binary()
  def to_binary(%__MODULE__{} = ordered_message) do
    ordered_message |> to_iodata() |> IO.iodata_to_binary()
  end

  ## Private header ordering implementation

  defp do_ordered_headers(headers) do
    # Extract Content-Length and other headers
    {content_length, other_headers} = Map.pop(headers, :content_length)

    # Format other headers first
    other_headers_iodata =
      other_headers
      |> Map.to_list()
      |> Enum.map(fn {name, value} -> format_header(name, value) end)

    # Format Content-Length last
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
    # Use Sippet's internal header formatting logic
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

  # Header name mapping (copied from Sippet.Message internals)
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
      other when is_atom(other) -> {format_header_name(other), false}
      other when is_binary(other) -> {other, false}
    end
  end

  defp format_header_name(atom) do
    atom
    |> to_string()
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join("-")
  end

  # Header value formatting (simplified version of Sippet's internal logic)
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

  defp format_header_value({display_name, %Sippet.URI{} = uri, %{} = parameters}) do
    display_part = if display_name != "", do: [display_name, " "], else: ""
    [display_part, "<", Sippet.URI.to_string(uri), ">", format_parameters(parameters)]
  end

  defp format_header_value({scheme, %{} = parameters}) when is_binary(scheme) do
    [scheme, format_parameters(parameters)]
  end

  defp format_header_value(value), do: to_string(value)

  defp format_parameters(%{} = parameters) when map_size(parameters) == 0, do: ""
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
    # Simple quoting logic - quote if contains special chars
    if String.contains?(value, [" ", ",", ";", "="]) do
      ["\"", value, "\""]
    else
      value
    end
  end
  defp maybe_quote_value(value), do: to_string(value)

  ## Protocol implementations for transparency

  # Make OrderedMessage work transparently with Sippet functions
  defimpl Inspect do
    def inspect(%Sippet.OrderedMessage{inner_message: message}, opts) do
      Inspect.inspect(message, opts)
    end
  end

  # Custom String.Chars implementation for ordered serialization
  defimpl String.Chars do
    def to_string(%Sippet.OrderedMessage{} = ordered_message) do
      Sippet.OrderedMessage.to_binary(ordered_message)
    end
  end

  ## Convenience functions for extracting inner message when needed

  @doc """
  Extracts the inner Sippet.Message for functions that specifically require it.
  """
  @spec unwrap(t()) :: Message.t()
  def unwrap(%__MODULE__{inner_message: message}), do: message

  @doc """
  Creates a new OrderedMessage by applying a function to the inner message.
  """
  @spec map(t(), (Message.t() -> Message.t())) :: t()
  def map(%__MODULE__{inner_message: message} = ordered_msg, fun) when is_function(fun, 1) do
    %{ordered_msg | inner_message: fun.(message)}
  end

  ## Delegation helpers for common Message functions

  defdelegate validate(ordered_message), to: __MODULE__, as: :validate_inner
  defdelegate has_header?(ordered_message, header), to: __MODULE__, as: :has_header_inner

  def validate_inner(%__MODULE__{inner_message: message}), do: Message.validate(message)
  def has_header_inner(%__MODULE__{inner_message: message}, header), do: Message.has_header?(message, header)
end
