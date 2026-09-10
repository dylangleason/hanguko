defmodule Hanguko.Korean do
  @moduledoc """
  Pure helpers for working with Korean text.

  Precomposed Hangul syllables live in the Unicode block U+AC00..U+D7A3 and are
  laid out arithmetically:

      code point = 0xAC00 + (initial * 21 + medial) * 28 + final

  with 19 initial consonants, 21 medial vowels and 28 finals (index 0 meaning
  "no final consonant"). Jamo are exposed as Hangul *compatibility* jamo
  (U+3131..U+318E), which is how they are typed and displayed on their own.
  """

  @syllable_base 0xAC00
  @syllable_last 0xD7A3
  @medial_count 21
  @final_count 28

  @initials ~w(ㄱ ㄲ ㄴ ㄷ ㄸ ㄹ ㅁ ㅂ ㅃ ㅅ ㅆ ㅇ ㅈ ㅉ ㅊ ㅋ ㅌ ㅍ ㅎ)
  @medials ~w(ㅏ ㅐ ㅑ ㅒ ㅓ ㅔ ㅕ ㅖ ㅗ ㅘ ㅙ ㅚ ㅛ ㅜ ㅝ ㅞ ㅟ ㅠ ㅡ ㅢ ㅣ)
  @finals [nil | ~w(ㄱ ㄲ ㄳ ㄴ ㄵ ㄶ ㄷ ㄹ ㄺ ㄻ ㄼ ㄽ ㄾ ㄿ ㅀ ㅁ ㅂ ㅄ ㅅ ㅆ ㅇ ㅈ ㅊ ㅋ ㅌ ㅍ ㅎ)]

  # Revised Romanization, letter by letter (no sound-change rules).
  @initial_roman ~w(g kk n d tt r m b pp s ss) ++ [""] ++ ~w(j jj ch k t p h)
  @medial_roman ~w(a ae ya yae eo e yeo ye o wa wae oe yo u wo we wi yu eu ui i)
  @final_roman ["" | ~w(k k k n n n t l k m l l l p l m p p t t ng t t k t p t)]

  @initial_index @initials |> Enum.with_index() |> Map.new()
  @medial_index @medials |> Enum.with_index() |> Map.new()
  @final_index @finals |> Enum.with_index() |> Map.new()

  @initial_tuple List.to_tuple(@initials)
  @medial_tuple List.to_tuple(@medials)
  @final_tuple List.to_tuple(@finals)
  @initial_roman_tuple List.to_tuple(@initial_roman)
  @medial_roman_tuple List.to_tuple(@medial_roman)
  @final_roman_tuple List.to_tuple(@final_roman)

  @doc "The 19 consonants that can start a syllable, in Unicode order."
  def initials, do: @initials

  @doc "The 21 vowels that can form the middle of a syllable, in Unicode order."
  def medials, do: @medials

  @doc "The 27 consonants and clusters that can end a syllable, in Unicode order."
  def finals, do: tl(@finals)

  @doc """
  Returns true if `char` is a single precomposed Hangul syllable.

      iex> Hanguko.Korean.syllable?("한")
      true
      iex> Hanguko.Korean.syllable?("ㅎ")
      false
  """
  def syllable?(<<cp::utf8>>) when cp in @syllable_base..@syllable_last, do: true
  def syllable?(_), do: false

  @doc """
  Splits a Hangul syllable into `{initial, medial, final}` compatibility jamo.
  `final` is `nil` for open syllables. Returns `nil` for anything that is not
  a single precomposed syllable.

      iex> Hanguko.Korean.decompose("한")
      {"ㅎ", "ㅏ", "ㄴ"}
      iex> Hanguko.Korean.decompose("가")
      {"ㄱ", "ㅏ", nil}
      iex> Hanguko.Korean.decompose("a")
      nil
  """
  def decompose(<<cp::utf8>>) when cp in @syllable_base..@syllable_last do
    {i, m, f} = indices(cp)
    {elem(@initial_tuple, i), elem(@medial_tuple, m), elem(@final_tuple, f)}
  end

  def decompose(_), do: nil

  @doc """
  Builds a syllable from compatibility jamo. `final` may be `nil` or `""`.

      iex> Hanguko.Korean.compose("ㅎ", "ㅏ", "ㄴ")
      {:ok, "한"}
      iex> Hanguko.Korean.compose("ㄱ", "ㅏ")
      {:ok, "가"}
      iex> Hanguko.Korean.compose("ㄳ", "ㅏ")
      :error
  """
  def compose(initial, medial, final \\ nil)

  def compose(initial, medial, ""), do: compose(initial, medial, nil)

  def compose(initial, medial, final) do
    with {:ok, i} <- Map.fetch(@initial_index, initial),
         {:ok, m} <- Map.fetch(@medial_index, medial),
         {:ok, f} <- Map.fetch(@final_index, final) do
      {:ok, <<@syllable_base + (i * @medial_count + m) * @final_count + f::utf8>>}
    end
  end

  @doc """
  Returns the final consonant (batchim) of the last character of `word`, or
  `nil` if it has none or the last character is not a Hangul syllable.
  Surrounding whitespace is ignored.

      iex> Hanguko.Korean.final_consonant("책")
      "ㄱ"
      iex> Hanguko.Korean.final_consonant("커피")
      nil
  """
  def final_consonant(word) when is_binary(word) do
    case word |> String.trim() |> String.last() |> decompose() do
      {_, _, final} -> final
      nil -> nil
    end
  end

  @doc """
  Returns true if the last syllable of `word` ends in a consonant. Used to pick
  particle and ending forms such as 은/는, 이/가, 을/를 and 이에요/예요.

      iex> Hanguko.Korean.has_batchim?("학생")
      true
      iex> Hanguko.Korean.has_batchim?("의사")
      false
  """
  def has_batchim?(word), do: final_consonant(word) != nil

  @doc """
  Breaks text into a flat list of compatibility jamo. Characters that are not
  Hangul syllables are passed through unchanged.

      iex> Hanguko.Korean.to_jamo("한 글")
      ["ㅎ", "ㅏ", "ㄴ", " ", "ㄱ", "ㅡ", "ㄹ"]
  """
  def to_jamo(text) when is_binary(text) do
    text
    |> String.graphemes()
    |> Enum.flat_map(fn char ->
      case decompose(char) do
        {i, m, nil} -> [i, m]
        {i, m, f} -> [i, m, f]
        nil -> [char]
      end
    end)
  end

  @doc """
  Letter-by-letter Revised Romanization. Sound-change rules (liaison,
  assimilation, etc.) are *not* applied, so this is only suitable for showing
  how individual syllables are spelled; curated content carries its own
  romanization.

      iex> Hanguko.Korean.romanize("한글")
      "hangeul"
  """
  def romanize(text) when is_binary(text) do
    text
    |> String.graphemes()
    |> Enum.map_join(fn
      <<cp::utf8>> when cp in @syllable_base..@syllable_last ->
        {i, m, f} = indices(cp)

        elem(@initial_roman_tuple, i) <>
          elem(@medial_roman_tuple, m) <> elem(@final_roman_tuple, f)

      char ->
        char
    end)
  end

  @doc """
  Normalizes a typed answer for comparison: Unicode NFC, lowercase,
  punctuation removed and whitespace collapsed.

      iex> Hanguko.Korean.normalize("  안녕하세요?! ")
      "안녕하세요"
      iex> Hanguko.Korean.normalize("Thank   you.")
      "thank you"
  """
  def normalize(text) when is_binary(text) do
    text
    |> :unicode.characters_to_nfc_binary()
    |> String.downcase()
    |> String.replace(~r/[\p{P}\p{S}]/u, "")
    |> String.split()
    |> Enum.join(" ")
  end

  defp indices(cp) do
    offset = cp - @syllable_base
    final = rem(offset, @final_count)
    medial = offset |> div(@final_count) |> rem(@medial_count)
    initial = div(offset, @final_count * @medial_count)
    {initial, medial, final}
  end
end
