package("ros")

set_homepage("https://github.com/imhutugui/ros")

set_description("ROS is a set of tools and libraries for robotic software development.")

add_urls("https://github.com/imhutugui/ros/archive/refs/tags/$(version).tar.gz")

add_versions("0.0.1", "26ede7fd61e33c3635bf2d6657ae4040a4a75c82a5da88855fd965db2f834025")

if is_plat("windows") then
    on_install(function (package)
        local configs = {shared = true}
        import("package.tools.xmake").install(package, configs)
    end)
end