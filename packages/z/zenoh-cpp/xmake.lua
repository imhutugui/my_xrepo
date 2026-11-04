package("zenoh-cpp")
    set_kind("library", {headeronly = true})
    set_homepage("https://github.com/eclipse-zenoh/zenoh-cpp")
    set_description("C++ bindings for Eclipse zenoh, as a zero cost header wrapper on top of zenoh-c")
    set_license("EPL-2.0 OR Apache-2.0")

    -- Submodules carry the backends themselves; zenoh-c comes from the zenoh-c package instead.
    add_urls("https://github.com/eclipse-zenoh/zenoh-cpp.git", {submodules = false})

    add_versions("1.10.2", "20eb0bef670e150d3750ca0739dcb28cd7909e2e")

    add_deps("zenoh-c 1.10.1")

    -- Upstream exports this as an INTERFACE definition of the zenohcxx::zenohc target.
    add_defines("ZENOHCXX_ZENOHC")

    -- The zenohcxx target is INTERFACE only, so installing the headers is all there is to do.
    on_install(function (package)
        os.cp("include", package:installdir())
    end)

    on_test(function (package)
        assert(package:check_cxxsnippets({test = [[
            #include <zenoh.hxx>
            void test() {
                auto config = zenoh::Config::create_default();
                zenoh::KeyExpr keyexpr("demo/example/test");
                (void)config;
                (void)keyexpr;
            }
        ]]}, {configs = {languages = "c++17"}}))
    end)
package_end()
