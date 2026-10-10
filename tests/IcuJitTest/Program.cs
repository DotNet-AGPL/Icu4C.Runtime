using System.Globalization;
using System.Text;

// Broad "does app-local ICU actually work" check. Exercises code paths that go through
// ICU (collation, formatting, normalization, case mapping, IDN, parsing) so the run fails
// loudly if the ICU binaries are not loaded. Exits non-zero on any failure.

int failures = 0;
void Check(string name, bool ok, string? detail = null)
{
    Console.WriteLine($"{(ok ? "PASS" : "FAIL")}  {name}{(detail is null ? "" : "  -> " + detail)}");
    if (!ok) failures++;
}

// 1) Culture data available and localized (not invariant fallback).
var zh = new CultureInfo("zh-CN");
Check("zh-CN Name == zh-CN", zh.Name == "zh-CN");
Check("zh-CN DisplayName localized", zh.DisplayName != "zh-CN", zh.DisplayName);
Check("zh-CN NativeName non-empty", !string.IsNullOrEmpty(zh.NativeName), zh.NativeName);

// 2) ICU ships hundreds of specific cultures.
int cultureCount = CultureInfo.GetCultures(CultureTypes.SpecificCultures).Length;
Check("specific cultures > 100", cultureCount > 100, cultureCount.ToString());

// 3) Collation: pinyin ordering for zh-CN (李 "li" sorts before 张 "zhang").
int zhCmp = string.Compare("张三", "李四", false, zh);
Check("zh-CN pinyin: 李四 < 张三", zhCmp > 0, zhCmp.ToString());

// 4) Locale-sensitive collation.
var sv = new CultureInfo("sv-SE");
int svCmp = string.Compare("ä", "z", false, sv);
Check("sv-SE: 'ä' sorts after 'z'", svCmp > 0, svCmp.ToString());
int enCmp = string.Compare("a", "B", true, new CultureInfo("en-US"));
Check("en-US ignore-case: a < B", enCmp < 0, enCmp.ToString());

// 5) Number formatting / parsing.
var de = new CultureInfo("de-DE");
string deN = (1234.56).ToString("N2", de);
Check("de-DE N2 == 1.234,56", deN == "1.234,56", deN);
Check("de-DE parse 1.234,56", Math.Abs(double.Parse("1.234,56", de) - 1234.56) < 1e-9);
string frN = (1234.56).ToString("N2", new CultureInfo("fr-FR"));
Check("fr-FR N2 value", frN.Contains("234,56"), frN);
string deCur = (1234.5).ToString("C", de);
Check("de-DE currency contains €", deCur.Contains("€"), deCur);

// 6) Case mapping (Turkish dotted I).
var tr = new CultureInfo("tr-TR");
Check("tr-TR ToUpper('i') == İ", "i".ToUpper(tr) == "\u0130", "i".ToUpper(tr));

// 7) Unicode normalization (NFC/NFD).
string composed = "\u00e9"; // é
string decomposed = composed.Normalize(NormalizationForm.FormD);
Check("NFD é -> 2 code units", decomposed.Length == 2, decomposed.Length.ToString());
Check("NFC round-trip", decomposed.Normalize(NormalizationForm.FormC) == composed);

// 8) IDN / punycode (ICU IDNA).
var idn = new IdnMapping();
string ascii = idn.GetAscii("bücher.de");
Check("IDN bücher.de -> xn--bcher-kva.de", ascii == "xn--bcher-kva.de", ascii);

// 9) Date formatting / parsing.
Check("ja-JP date yyyy-MM-dd",
    new DateTime(2026, 10, 10).ToString("yyyy-MM-dd", new CultureInfo("ja-JP")) == "2026-10-10");

// 10) Time zones.
Check("TimeZoneInfo.Local available", !string.IsNullOrEmpty(TimeZoneInfo.Local.Id), TimeZoneInfo.Local.Id);

// 11) Culture-aware string search.
var ci = new CultureInfo("en-US").CompareInfo;
Check("ignore-case IndexOf", ci.IndexOf("Hello World", "WORLD", CompareOptions.IgnoreCase) >= 0);

// 12) Surrogates (UTF-16 length).
Check("emoji is 2 UTF-16 units", "👍".Length == 2);

Console.WriteLine();
Console.WriteLine(failures == 0 ? "ALL CHECKS PASSED" : $"{failures} CHECK(S) FAILED");
return failures == 0 ? 0 : 1;
