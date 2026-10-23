package("lie-plusplus")
    set_kind("library", {headeronly = true})
    set_homepage("https://github.com/aau-cns/Lie-plusplus")
    set_description("Header-only C++17 library for Lie group operations based on Eigen")
    set_license("Apache-2.0")

    add_urls("https://github.com/aau-cns/Lie-plusplus.git")

    add_versions("2026.07.03", "ec459c38445d986b5830162ae428b8b242ce5021")

    add_deps("eigen 3.4.0")

    -- Upstream has no CMake install rules and fetches Eigen via FetchContent, so install headers directly.
    on_install(function (package)
        os.cp("include", package:installdir())
    end)

    on_test(function (package)
        assert(package:check_cxxsnippets({test = [[
            #include <groups/SO3.hpp>
            #include <groups/SEn3.hpp>
            #include <groups/Gal3.hpp>
            #include <groups/SOT3.hpp>
            #include <groups/TG.hpp>
            #include <groups/SDB.hpp>
            #include <groups/In.hpp>
            #include <utils/tools.hpp>
            void test() {
                using SO3d = group::SO3<double>;
                using SE23d = group::SEn3<double, 2>;
                SO3d R;
                SE23d X = SE23d::exp(SE23d::VectorType::Zero());
                (void)R;
                (void)X;
            }
        ]]}, {configs = {languages = "c++17"}}))
    end)
package_end()
