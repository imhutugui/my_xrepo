package("rosbag")
    set_kind("library", {headeronly = true})
    set_homepage("http://github.com/imhutugui/ros/")
    set_description("The ROS bag library provides a way to access ROS bag files on windows")
    set_license("BSD")

    set_urls("http://github.com/imhutugui/ros.git")
    add_versions("v0.1", "fd0a4f651ab3956b0b77d7eb76d0be6bf8f23791")


    on_install(function(package)
        os.cp("include/*", package:installdir("include"))
        os.cp("ros_comm/clients/roscpp/include/*" , package:installdir("include"))
        os.cp("ros_comm/tools/rosbag_storage/include/*" , package:installdir("include"))
        os.cp("roscpp_core/cpp_common/include/*" , package:installdir("include"))
        os.cp("roscpp_core/roscpp_serialization/include/*" , package:installdir("include"))
        os.cp("roscpp_core/roscpp_traits/include", package:installdir("include"))
        os.cp("ros_comm/utilities/roslz4/include", package:installdir("include"))
        os.cp("console_bridge/include", package:installdir("include"))
        local configs = {}
        import("package.tools.xmake").install(package, configs)
    end)

    on_load(function (package)
        package:set("installdir", path.join(os.scriptdir(), package:plat(), package:arch(), package:mode()))
    end)

    on_fetch(function (package)
        local result = {}
        local libfiledir = (package:config("shared") and package:is_plat("windows", "mingw")) and "bin" or "lib"
        result.links = "rosbag"
        result.linkdirs = package:installdir("lib")
        result.includedirs = package:installdir("include")
        result.libfiles = path.join(package:installdir(libfiledir), "rosbag.dll")
        return result
    end)