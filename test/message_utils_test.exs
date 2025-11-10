defmodule Sippet.MessageUtilsTest do
  use ExUnit.Case, async: true

  alias Sippet.Message
  alias Sippet.MessageUtils
  alias Sippet.URI

  describe "to_string_with_content_length_last/1" do
    test "places Content-Length header as the last header" do
      # Build a message with multiple headers
      message =
        Message.build_request(:invite, "sip:user@example.com")
        |> Message.put_header(:via, {{2, 0}, :udp, {"proxy.com", 5060}, %{"branch" => "z9hG4bK123"}})
        |> Message.put_header(:from, {"Alice", URI.parse("sip:alice@example.com"), %{"tag" => "abc123"}})
        |> Message.put_header(:to, {"Bob", URI.parse("sip:bob@example.com"), %{}})
        |> Message.put_header(:call_id, "call123@example.com")
        |> Message.put_header(:cseq, {1, :invite})
        |> Message.put_header(:max_forwards, 70)
        |> Message.put_header(:content_type, {{"application", "sdp"}, %{}})

      result = MessageUtils.to_string_with_content_length_last(message)

      # Split into lines and check that Content-Length is the last header
      lines = String.split(result, "\r\n")

      # Find the empty line that separates headers from body
      empty_line_index = Enum.find_index(lines, &(&1 == ""))

      # Get all header lines (before the empty line)
      header_lines = Enum.slice(lines, 1, empty_line_index - 1)

      # The last header line should be Content-Length
      last_header = List.last(header_lines)

      assert String.starts_with?(last_header, "Content-Length:")
      assert String.contains?(result, "Content-Length: 0")
    end

    test "adds Content-Length header if not present" do
      message =
        Message.build_request(:register, "sip:registrar.example.com")
        |> Message.put_header(:via, {{2, 0}, :udp, {"client.com", 5060}, %{"branch" => "z9hG4bKabc"}})
        |> Message.put_header(:from, {"User", URI.parse("sip:user@example.com"), %{"tag" => "tag1"}})
        |> Message.put_header(:to, {"User", URI.parse("sip:user@example.com"), %{}})
        |> Message.put_header(:call_id, "register123@example.com")
        |> Message.put_header(:cseq, {1, :register})

      result = MessageUtils.to_string_with_content_length_last(message)

      # Should add Content-Length: 0 since there's no body
      assert String.contains?(result, "Content-Length: 0")

      # And it should be the last header
      lines = String.split(result, "\r\n")
      empty_line_index = Enum.find_index(lines, &(&1 == ""))
      header_lines = Enum.slice(lines, 1, empty_line_index - 1)
      last_header = List.last(header_lines)

      assert String.starts_with?(last_header, "Content-Length:")
    end

    test "correctly calculates Content-Length for messages with body" do
      body = "v=0\r\no=alice 123456 654321 IN IP4 host.example.com\r\n"

      message =
        Message.build_request(:invite, "sip:user@example.com")
        |> Message.put_header(:via, {{2, 0}, :udp, {"proxy.com", 5060}, %{"branch" => "z9hG4bK456"}})
        |> Message.put_header(:from, {"Alice", URI.parse("sip:alice@example.com"), %{"tag" => "tag2"}})
        |> Message.put_header(:to, {"Bob", URI.parse("sip:bob@example.com"), %{}})
        |> Message.put_header(:call_id, "invite123@example.com")
        |> Message.put_header(:cseq, {1, :invite})
        |> Message.put_header(:content_type, {{"application", "sdp"}, %{}})
        |> Message.put_body(body)

      result = MessageUtils.to_string_with_content_length_last(message)

      expected_length = String.length(body)
      assert String.contains?(result, "Content-Length: #{expected_length}")

      # Verify Content-Length is last header
      lines = String.split(result, "\r\n")
      empty_line_index = Enum.find_index(lines, &(&1 == ""))
      header_lines = Enum.slice(lines, 1, empty_line_index - 1)
      last_header = List.last(header_lines)

      assert String.starts_with?(last_header, "Content-Length:")

      # Verify body is preserved
      assert String.ends_with?(result, body)
    end

    test "preserves existing Content-Length value if already set" do
      message =
        Message.build_request(:invite, "sip:user@example.com")
        |> Message.put_header(:via, {{2, 0}, :udp, {"proxy.com", 5060}, %{"branch" => "z9hG4bK789"}})
        |> Message.put_header(:from, {"Alice", URI.parse("sip:alice@example.com"), %{"tag" => "tag3"}})
        |> Message.put_header(:to, {"Bob", URI.parse("sip:bob@example.com"), %{}})
        |> Message.put_header(:call_id, "test123@example.com")
        |> Message.put_header(:cseq, {1, :invite})
        |> Message.put_header(:content_length, 150)  # Explicitly set content length

      result = MessageUtils.to_string_with_content_length_last(message)

      # Should preserve the explicitly set Content-Length value
      assert String.contains?(result, "Content-Length: 150")

      # And it should still be the last header
      lines = String.split(result, "\r\n")
      empty_line_index = Enum.find_index(lines, &(&1 == ""))
      header_lines = Enum.slice(lines, 1, empty_line_index - 1)
      last_header = List.last(header_lines)

      assert String.starts_with?(last_header, "Content-Length:")
    end
  end

  describe "to_iodata_with_content_length_last/1" do
    test "returns iodata with Content-Length as last header" do
      message =
        Message.build_request(:options, "sip:server.example.com")
        |> Message.put_header(:via, {{2, 0}, :udp, {"client.com", 5060}, %{"branch" => "z9hG4bKopt"}})
        |> Message.put_header(:from, {"Client", URI.parse("sip:client@example.com"), %{"tag" => "opt1"}})
        |> Message.put_header(:to, {"Server", URI.parse("sip:server@example.com"), %{}})
        |> Message.put_header(:call_id, "options123@example.com")
        |> Message.put_header(:cseq, {1, :options})

      iodata = MessageUtils.to_iodata_with_content_length_last(message)
      result = IO.iodata_to_binary(iodata)

      # Should contain Content-Length header
      assert String.contains?(result, "Content-Length: 0")

      # Should be valid iodata
      assert is_list(iodata) or is_binary(iodata)

      # Content-Length should be last header
      lines = String.split(result, "\r\n")
      empty_line_index = Enum.find_index(lines, &(&1 == ""))
      header_lines = Enum.slice(lines, 1, empty_line_index - 1)
      last_header = List.last(header_lines)

      assert String.starts_with?(last_header, "Content-Length:")
    end
  end

  describe "reorder_headers_for_content_length_last/1" do
    test "returns a message with reordered headers map" do
      original_message =
        Message.build_request(:invite, "sip:user@example.com")
        |> Message.put_header(:via, {{2, 0}, :udp, {"proxy.com", 5060}, %{"branch" => "z9hG4bKreorder"}})
        |> Message.put_header(:from, {"Alice", URI.parse("sip:alice@example.com"), %{"tag" => "reorder1"}})
        |> Message.put_header(:to, {"Bob", URI.parse("sip:bob@example.com"), %{}})
        |> Message.put_header(:call_id, "reorder123@example.com")
        |> Message.put_header(:cseq, {1, :invite})

      reordered_message = MessageUtils.reorder_headers_for_content_length_last(original_message)

      # Should have the same headers
      assert map_size(reordered_message.headers) == map_size(original_message.headers) + 1  # +1 for added content_length
      assert Map.has_key?(reordered_message.headers, :content_length)
      assert reordered_message.headers.content_length == 0

      # Should preserve other message fields
      assert reordered_message.start_line == original_message.start_line
      assert reordered_message.body == original_message.body
      assert reordered_message.target == original_message.target
    end

    test "adds Content-Length if not present" do
      message =
        Message.build_request(:register, "sip:registrar.example.com")
        |> Message.put_header(:via, {{2, 0}, :udp, {"client.com", 5060}, %{"branch" => "z9hG4bKreg"}})

      result = MessageUtils.reorder_headers_for_content_length_last(message)

      assert Map.has_key?(result.headers, :content_length)
      assert result.headers.content_length == 0
    end

    test "preserves existing Content-Length" do
      message =
        Message.build_request(:invite, "sip:user@example.com")
        |> Message.put_header(:content_length, 200)
        |> Message.put_header(:via, {{2, 0}, :udp, {"proxy.com", 5060}, %{"branch" => "z9hG4bKpres"}})

      result = MessageUtils.reorder_headers_for_content_length_last(message)

      assert result.headers.content_length == 200
    end
  end

  describe "integration with standard Message.to_string/1" do
    test "comparison shows different header ordering" do
      message =
        Message.build_request(:invite, "sip:user@example.com")
        |> Message.put_header(:via, {{2, 0}, :udp, {"proxy.com", 5060}, %{"branch" => "z9hG4bKcomp"}})
        |> Message.put_header(:from, {"Alice", URI.parse("sip:alice@example.com"), %{"tag" => "comp1"}})
        |> Message.put_header(:to, {"Bob", URI.parse("sip:bob@example.com"), %{}})
        |> Message.put_header(:call_id, "compare123@example.com")
        |> Message.put_header(:cseq, {1, :invite})

      standard_result = Message.to_string(message)
      custom_result = MessageUtils.to_string_with_content_length_last(message)

      # Both should contain the same headers
      assert String.contains?(standard_result, "Content-Length:")
      assert String.contains?(custom_result, "Content-Length:")

      # Both should be valid SIP messages
      assert String.starts_with?(standard_result, "INVITE sip:user@example.com SIP/2.0")
      assert String.starts_with?(custom_result, "INVITE sip:user@example.com SIP/2.0")

      # Custom version should have Content-Length as last header
      custom_lines = String.split(custom_result, "\r\n")
      custom_empty_index = Enum.find_index(custom_lines, &(&1 == ""))
      custom_header_lines = Enum.slice(custom_lines, 1, custom_empty_index - 1)
      custom_last_header = List.last(custom_header_lines)

      assert String.starts_with?(custom_last_header, "Content-Length:")
    end
  end
end
