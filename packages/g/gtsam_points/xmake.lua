package("gtsam_points")
    set_homepage("https://github.com/koide3/gtsam_points")
    set_description("A collection of GTSAM factors and optimizers for point cloud SLAM")
    set_license("MIT")

    add_urls("https://github.com/koide3/gtsam_points.git")

    add_versions("1.2.1", "620ad2786833601c81453eb7ad09a24d4331063a")

    add_deps("cmake", "gtsam 4.2.1", "eigen")
    add_deps("boost", {configs = {graph = true, filesystem = true}})

    on_load(function (package)
        -- TBB is optional and not commonly available on Windows
        if not package:is_plat("windows") then
            package:add("deps", "tbb")
        end
    end)

    on_install(function (package)
        local sourcedir = path.join(package:cachedir(), "source", "gtsam_points")

        -- MSVC does not allow default arguments in explicit template instantiation
        -- Fix: remove "= Eigen::Isometry3d::Identity" from fast_occupancy_grid.cpp
        local foo_file = path.join(sourcedir, "src", "gtsam_points", "ann", "fast_occupancy_grid.cpp")
        if os.isfile(foo_file) then
            local content = io.readfile(foo_file)
            if content and content:find("= Eigen::Isometry3d::Identity()") then
                content = content:gsub("= Eigen::Isometry3d::Identity()%(%)", "")
                io.writefile(foo_file, content)
            end
        end

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
            if not package:is_plat("windows") then
                table.insert(configs, "-DCMAKE_POSITION_INDEPENDENT_CODE=ON")
            end
        end
        if package:is_plat("windows") then
            -- MSVC has limited OpenMP support; disable to avoid build issues
            table.insert(configs, "-DBUILD_WITH_TBB=OFF")
            table.insert(configs, "-DBUILD_WITH_OPENMP=OFF")
            -- MSVC does not support -fPIC
            table.insert(configs, "-DCMAKE_POSITION_INDEPENDENT_CODE=OFF")
        else
            table.insert(configs, "-DBUILD_WITH_TBB=ON")
            table.insert(configs, "-DBUILD_WITH_OPENMP=ON")
        end
        import("package.tools.cmake").install(package, configs)
    end)

    on_test(function (package)
        assert(package:check_cxxsnippets({test = [[
            #include <gtsam_points/types/point_cloud.hpp>
            void test() {
                gtsam_points::PointCloud cloud;
            }
        ]]}))
    end)
package_end()