package("gtsam")
    set_homepage("https://github.com/borglab/gtsam")
    set_description("Georgia Tech Smoothing and Mapping library - factor graph optimization for SLAM and SFM")

    add_urls("https://github.com/borglab/gtsam.git")

    add_versions("4.2.0", "4f66a491ffc83cf092d0d818b11dc35135521612")
    add_versions("4.2.1", "0a070c2700fcf6fc7b960da8d734bbd02043c89a")

    add_deps("cmake")
    add_deps("eigen 3.4.0")
    add_deps("boost", {configs = {serialization = true, filesystem = true, thread = true,
                                 program_options = true, date_time = true, timer = true,
                                 chrono = true, graph = true}})

    on_load(function (package)
        -- TBB is optional; skip on Windows due to build complexity
        if not package:is_plat("windows") then
            package:add("deps", "tbb")
        end

        if package:is_plat("windows") then
            -- GTSAM uses UnDecorateSymbolName from Dbghelp.lib in its demangle function.
            -- When built as a static library, the PRIVATE link in GTSAM's CMakeLists.txt
            -- doesn't propagate, so consumers need to link Dbghelp explicitly.
            package:add("syslinks", "dbghelp")
        end
    end)

    on_install("windows", "linux", "macosx", function (package)
        local configs = {}

        -- GTSAM CMake options (use :BOOL type prefix to override option() defaults)
        -- Without :BOOL, CMake option() treats the cache entry as UNINITIALIZED
        -- and overwrites it with its own default (OFF), causing version mismatch.
        table.insert(configs, "-DGTSAM_BUILD_TESTS:BOOL=OFF")
        table.insert(configs, "-DGTSAM_BUILD_EXAMPLES_ALWAYS:BOOL=OFF")
        table.insert(configs, "-DGTSAM_BUILD_UNSTABLE:BOOL=ON")
        table.insert(configs, "-DGTSAM_INSTALL_MATLAB_TOOLBOX:BOOL=OFF")
        table.insert(configs, "-DGTSAM_BUILD_PYTHON:BOOL=OFF")
        table.insert(configs, "-DGTSAM_USE_SYSTEM_EIGEN:BOOL=ON")
        table.insert(configs, "-DGTSAM_BUILD_WITH_MARCH_NATIVE:BOOL=OFF")
        table.insert(configs, "-DGTSAM_WITH_TBB:BOOL=OFF")

        -- xmake auto-sets: CMAKE_BUILD_TYPE, BUILD_SHARED_LIBS, CMAKE_INSTALL_PREFIX,
        -- CMAKE_PREFIX_PATH (from deps), CMAKE_POSITION_INDEPENDENT_CODE, etc.
        -- So we don't need to set them manually.

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
