package("nano_gicp")
    set_homepage("https://github.com/koide3/nano_gicp")
    set_description("Nano GICP - Lightweight GICP implementation for point cloud registration")
    set_license("MIT")

    add_urls("https://github.com/koide3/nano_gicp/archive/refs/tags/{version}.tar.gz")

    add_versions("0.1.0", "c8d12e5f237b9bb733413bc3334f42e5e78c2f4d")

    add_deps("cmake")
    add_deps("eigen")
    add_deps("pcl")
    add_deps("nanoflann")

    on_load(function (package)
        package:add("includedirs", "include")
    end)

    on_install(function (package)
        local deps = { "eigen", "pcl", "nanoflann" }
        for _, depname in ipairs(deps) do
            local dep = package:dep(depname)
            if dep then
                package:add("includedirs", dep:installdir(), depname)
            end
        end

        import("package.tools.cmake").install(package, {
            configs = {
                "-DBUILD_EXAMPLES=OFF",
                "-DBUILD_TESTS=OFF",
            },
            cxxflags = "/DNOMINMAX /D_USE_MATH_DEFINES /EHsc",
        })
    end)

package_end()
