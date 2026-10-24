package("kalmanif")
    set_kind("library", {headeronly = true})
    set_homepage("https://github.com/artivis/kalmanif")
    set_description("A small collection of Kalman filters on Lie groups")
    set_license("MIT")

    add_urls("https://github.com/artivis/kalmanif.git")

    add_versions("2023.04.13", "9a97a822d1aaac9e95c3fcc2dfaa20a5b50645c9")

    add_deps("cmake", "manif", "eigen 3.4.0")

    on_install(function (package)
        local configs = {
            "-DBUILD_TESTING=OFF",
            "-DBUILD_EXAMPLES=OFF",
            "-DPLOT_EXAMPLES=OFF",
            "-DENABLE_CPPCHECK=OFF",
            "-DENABLE_COVERAGE=OFF",
            "-DCMAKE_BUILD_TYPE=" .. (package:is_debug() and "Debug" or "Release"),
        }
        import("package.tools.cmake").install(package, configs)
    end)

    on_test(function (package)
        assert(package:check_cxxsnippets({test = [[
            #include <kalmanif/kalmanif.h>
            #include <manif/SE3.h>
            void test() {
                using State = manif::SE3d;
                kalmanif::ExtendedKalmanFilter<State> ekf;
                kalmanif::SquareRootExtendedKalmanFilter<State> sekf;
                kalmanif::InvariantExtendedKalmanFilter<State> iekf;
                kalmanif::UnscentedKalmanFilterManifolds<State> ukfm;
                (void)ekf;
                (void)sekf;
                (void)iekf;
                (void)ukfm;
            }
        ]]}, {configs = {languages = "c++17"}}))
    end)
package_end()
