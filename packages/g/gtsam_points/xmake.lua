package("gtsam_points")
    set_homepage("https://github.com/koide3/gtsam_points")
    set_description("A collection of GTSAM factors and optimizers for point cloud SLAM")
    set_license("MIT")

    add_urls("https://github.com/koide3/gtsam_points.git")

    add_versions("1.2.1", "85d0f4c43098b1f071bbb07710692e3829347c6c")

    add_deps("cmake", "gtsam", "eigen")
    add_deps("boost", {configs = {filesystem = true, graph = true}})

    on_load(function (package)
        -- TBB is optional and not commonly available on Windows
        if not package:is_plat("windows") then
            package:add("deps", "tbb")
        end
    end)

    on_install(function (package)
        local configs = {
            "-DBUILD_TESTS=OFF",
            "-DBUILD_DEMO=OFF",
            "-DBUILD_EXAMPLE=OFF",
            "-DBUILD_TOOLS=OFF",
            "-DBUILD_WITH_MARCH_NATIVE=OFF",
            "-DBUILD_WITH_CUDA=OFF",
        }
        if package:config("shared") then
            table.insert(configs, "-DBUILD_SHARED_LIBS=ON")
        else
            table.insert(configs, "-DBUILD_SHARED_LIBS=OFF")
            table.insert(configs, "-DCMAKE_POSITION_INDEPENDENT_CODE=ON")
        end
        if package:is_plat("windows") then
            -- MSVC has limited OpenMP support; disable to avoid build issues
            table.insert(configs, "-DBUILD_WITH_TBB=OFF")
            table.insert(configs, "-DBUILD_WITH_OPENMP=OFF")
        else
            table.insert(configs, "-DBUILD_WITH_TBB=ON")
            table.insert(configs, "-DBUILD_WITH_OPENMP=ON")
        end
        import("package.tools.cmake").install(package, configs)
    end)

    on_test(function (package)
        assert(package:has_cxx_include("gtsam_points/types/point_cloud.hpp"))
    end)
package_end()