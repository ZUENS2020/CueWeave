using CueWeave.WinUI.Services;

namespace CueWeave.Windows.Tests;

[TestClass]
public sealed class CoreRpcTests
{
    [TestMethod]
    public void ReadsChineseUtf8Payload()
    {
        var result = CoreRpc.ReadResult("""{"request_id":"r1","ok":true,"result":{"title":"晴天"}}"""u8, "r1");
        Assert.AreEqual("晴天", result.GetProperty("title").GetString());
    }

    [TestMethod]
    public void IgnoresTrailingJunkAfterTheEnvelope()
    {
        var result = CoreRpc.ReadResult(
            """{"request_id":"abc","ok":true,"result":{"protocol_version":1}}info leftover"""u8,
            "abc");
        Assert.AreEqual(1, result.GetProperty("protocol_version").GetInt32());
    }

    [TestMethod]
    public void MapsCoreErrorEnvelope()
    {
        var error = Assert.Throws<CoreException>(() =>
            CoreRpc.ReadResult("""{"request_id":"x","ok":false,"error":{"code":"core_error","message":"nope"}}"""u8, "x"));
        Assert.AreEqual("core_error", error.Code);
        Assert.AreEqual("nope", error.Message);
    }

    [TestMethod]
    public void SurfacesCoreErrorWhenRequestIdIsEmpty()
    {
        var error = Assert.Throws<CoreException>(() =>
            CoreRpc.ReadResult(
                """{"request_id":"","ok":false,"error":{"code":"invalid_request","message":"expected value at line 1 column 1"}}"""u8,
                "wanted"));
        Assert.AreEqual("invalid_request", error.Code);
        StringAssert.Contains(error.Message, "expected value");
    }

    [TestMethod]
    public void RejectsSuccessfulEnvelopeWithWrongRequestId()
    {
        var error = Assert.Throws<CoreException>(() =>
            CoreRpc.ReadResult("""{"request_id":"other","ok":true,"result":{}}"""u8, "wanted"));
        Assert.AreEqual("invalid_response", error.Code);
        Assert.AreEqual(L10n.T("error.coreMismatch"), error.Message);
    }

    [TestMethod]
    public void RejectsBrokenJsonTheSameWayTheDesktopDialogDid()
    {
        var error = Assert.Throws<CoreException>(() =>
            CoreRpc.ReadResult("""{"request_id":"z","ok":true,"result":{"title":"晴"id":1}}"""u8, "z"));
        Assert.AreEqual("invalid_response", error.Code);
        StringAssert.Contains(error.Message, "invalid after a value");
    }
}
