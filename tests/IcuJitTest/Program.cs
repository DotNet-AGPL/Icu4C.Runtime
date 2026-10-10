using System.Globalization;

var zh = new CultureInfo("zh-CN");
Console.WriteLine($"CurrentCulture   : {CultureInfo.CurrentCulture.Name}");
Console.WriteLine($"zh-CN DisplayName: {zh.DisplayName}");
Console.WriteLine($"zh-CN NativeName : {zh.NativeName}");
Console.WriteLine($"zh-CN Date       : {DateTime.Now.ToString("D", zh)}");
Console.WriteLine($"Sort 张三 vs 李四 : {string.Compare("张三", "李四", StringComparison.CurrentCulture)}");
var tz = TimeZoneInfo.Local;
Console.WriteLine($"TimeZone         : {tz.Id} / {tz.DisplayName}");
