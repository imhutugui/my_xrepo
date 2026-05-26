package("gtsam")
    set_homepage("https://github.com/borglab/gtsam")
    set_description("Georgia Tech Smoothing and Mapping library - factor graph optimization for SLAM and SFM")

    add_urls("https://github.com/borglab/gtsam.git")

    add_versions("4.2.0", "4f66a491ffc83cf092d0d818b11dc35135521612")
    add_versions("4.2.1", "0a070c2700fcf6fc7b960da8d734bbd02043c89a")
    add_versions("4.3a0", "3ad4b4c3cb28394c9597f48fa02dad361c8450e3")
    add_versions("4.3a1", "2f3e56c0ddbd3a1aa54ed043643b553d26a069f6")

    add_deps("cmake", "eigen")
    add_deps("boost",
             {configs = {serialization = true, filesystem = true, thread = true,
                         program_options = true, date_time = true, timer = true,
                         chrono = true, regex = true}})

    on_load(function (package)
        -- TBB is optional; skip on Windows due to build complexity
        if not package:is_plat("windows") then
            package:add("deps", "tbb")
        end
    end)

    on_install(function (package)
        local configs = {"-DGTSAM_BUILD_TESTS=OFF", "-DGTSAM_BUILD_EXAMPLES_ALWAYS=OFF",
                         "-DGTSAM_BUILD_UNSTABLE=ON", "-DGTSAM_INSTALL_MATLAB_TOOLBOX=OFF",
                         "-DGTSAM_BUILD_PYTHON=OFF",
                         "-DGTSAM_BUILD_WITH_MARCH_NATIVE=OFF"}
        if package:config("shared") then
            table.insert(configs, "-DBUILD_SHARED_LIBS=ON")
        else
            table.insert(configs, "-DBUILD_SHARED_LIBS=OFF")
        end
        if package:is_plat("windows") then
            table.insert(configs, "-DGTSAM_WITH_TBB=OFF")
        end
        if package:version():ge("4.3") then
            table.insert(configs, "-DGTSAM_USE_BOOST_FEATURES=ON")
            table.insert(configs, "-DGTSAM_ENABLE_BOOST_SERIALIZATION=ON")
        end
        import("package.tools.cmake").install(package, configs)
    end)

    on_test(function (package)
        assert(package:check_cxxsnippets({test = [[
            #include <gtsam/slam/BetweenFactor.h>
            #include <gtsam/geometry/Point2.h>
            void test() {
                gtsam::BetweenFactor<gtsam::Point2> f(1, 2, gtsam::Point2(), gtsam::noiseModel::Unit::Create(2));
            }
        ]]}))
    end)
package_end()
