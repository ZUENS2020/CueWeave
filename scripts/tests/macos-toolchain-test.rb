require "minitest/autorun"
require_relative "../check-macos-toolchain"

class MacOSToolchainTest < Minitest::Test
  def load_commands(sdk: "26.5", minimum: "14.0", platform: "1")
    "Load command 10\n      cmd LC_BUILD_VERSION\n  cmdsize 32\n platform #{platform}\n    minos #{minimum}\n      sdk #{sdk}\n   ntools 1\n     tool 3\n  version 1267.0\nLoad command 11\n      cmd LC_SOURCE_VERSION\n"
  end

  def test_pinned_toolchain
    MacOSBuildGate.verify_toolchain!("Xcode 26.5\nBuild version 17F42\n", "26.5\n")
    assert_equal 1, MacOSBuildGate.verify_binary!(load_commands)
  end

  def test_old_ci_toolchain_is_rejected
    assert_raises(RuntimeError) { MacOSBuildGate.verify_toolchain!("Xcode 16.4\n", "15.5") }
    assert_raises(RuntimeError) { MacOSBuildGate.verify_binary!(load_commands(sdk: "15.5")) }
  end

  def test_sdk_override_and_unreviewed_upgrade_are_rejected
    assert_raises(RuntimeError) { MacOSBuildGate.verify_toolchain!("Xcode 26.5\n", "15.5") }
    assert_raises(RuntimeError) { MacOSBuildGate.verify_toolchain!("Xcode 26.6\n", "26.5") }
    assert_raises(RuntimeError) { MacOSBuildGate.verify_binary!(load_commands(sdk: "27.0")) }
  end

  def test_deployment_target_must_not_increase
    assert_raises(RuntimeError) { MacOSBuildGate.verify_binary!(load_commands(minimum: "26.0")) }
  end

  def test_wrong_platform_and_missing_metadata_are_rejected
    assert_raises(RuntimeError) { MacOSBuildGate.verify_binary!(load_commands(platform: "2")) }
    assert_raises(RuntimeError) { MacOSBuildGate.verify_binary!("Load command 0\ncmd LC_VERSION_MIN_MACOSX\n") }
    assert_raises(RuntimeError) { MacOSBuildGate.verify_binary!(load_commands.sub("sdk 26.5", "sdk")) }
  end

  def test_every_universal_slice_is_checked
    assert_equal 2, MacOSBuildGate.verify_binary!(load_commands + load_commands)
    assert_raises(RuntimeError) { MacOSBuildGate.verify_binary!(load_commands + load_commands(sdk: "15.5")) }
  end
end
