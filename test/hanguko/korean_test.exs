defmodule Hanguko.KoreanTest do
  use ExUnit.Case, async: true

  alias Hanguko.Korean

  doctest Hanguko.Korean

  test "jamo inventories have the Unicode sizes" do
    assert length(Korean.initials()) == 19
    assert length(Korean.medials()) == 21
    assert length(Korean.finals()) == 27
  end

  test "decompose/compose round-trips every precomposed syllable" do
    for cp <- 0xAC00..0xD7A3 do
      syllable = <<cp::utf8>>
      {i, m, f} = Korean.decompose(syllable)
      assert Korean.compose(i, m, f) == {:ok, syllable}
    end
  end

  test "decompose handles open syllables and clusters" do
    assert Korean.decompose("나") == {"ㄴ", "ㅏ", nil}
    assert Korean.decompose("닭") == {"ㄷ", "ㅏ", "ㄺ"}
    assert Korean.decompose("쫘") == {"ㅉ", "ㅘ", nil}
    assert Korean.decompose("ㄱ") == nil
    assert Korean.decompose("한글") == nil
  end

  test "compose rejects jamo in the wrong position" do
    assert Korean.compose("ㅏ", "ㄱ") == :error
    assert Korean.compose("ㄱ", "ㅏ", "ㄸ") == :error
    assert Korean.compose("ㄱ", "ㅏ", "") == {:ok, "가"}
  end

  test "batchim detection looks at the last syllable" do
    assert Korean.has_batchim?("선생님")
    assert Korean.has_batchim?(" 물 ")
    refute Korean.has_batchim?("친구")
    refute Korean.has_batchim?("coffee")
    refute Korean.has_batchim?("")
    assert Korean.final_consonant("서울") == "ㄹ"
  end

  test "romanize spells syllables letter by letter" do
    assert Korean.romanize("안녕") == "annyeong"
    assert Korean.romanize("아이") == "ai"
    assert Korean.romanize("김치!") == "gimchi!"
    assert Korean.romanize("의사") == "uisa"
  end

  test "normalize makes typed answers comparable" do
    decomposed = :unicode.characters_to_nfd_binary("한국어")
    assert Korean.normalize(decomposed) == "한국어"
    assert Korean.normalize("Hello, World!") == "hello world"
  end
end
