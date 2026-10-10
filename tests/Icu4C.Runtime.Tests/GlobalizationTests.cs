using System.Globalization;
using Xunit;

namespace Icu4C.Runtime.Tests;

public class GlobalizationTests
{
    [Fact]
    public void ZhCn_Culture_Loads()
    {
        var zh = new CultureInfo("zh-CN");
        Assert.Equal("zh-CN", zh.Name);
        Assert.False(string.IsNullOrEmpty(zh.NativeName));
    }

    [Fact]
    public void Culture_Is_Not_Invariant()
    {
        // In invariant mode, DisplayName falls back to the culture name.
        var zh = new CultureInfo("zh-CN");
        Assert.NotEqual("zh-CN", zh.DisplayName);
    }

    [Fact]
    public void String_Comparison_Uses_Culture()
    {
        // Under ICU zh-CN collation (pinyin), 李 "li" sorts before 张 "zhang".
        var zh = new CultureInfo("zh-CN");
        Assert.True(string.Compare("张三", "李四", false, zh) > 0);
    }

    [Fact]
    public void Chinese_Date_Is_Culture_Aware()
    {
        var zh = new CultureInfo("zh-CN");
        var s = new DateTime(2026, 10, 10).ToString("D", zh);
        Assert.Contains("2026", s);
    }

    [Fact]
    public void TimeZone_Is_Available()
    {
        Assert.NotNull(TimeZoneInfo.Local);
        Assert.False(string.IsNullOrEmpty(TimeZoneInfo.Local.Id));
    }
}
