package("zenoh-c")
    set_homepage("https://github.com/eclipse-zenoh/zenoh-c")
    set_description("The C bindings for Eclipse zenoh")
    set_license("EPL-2.0 OR Apache-2.0")

    add_urls("https://github.com/eclipse-zenoh/zenoh-c.git")

    -- Commit pinned by zenoh-cpp 1.10.2
    add_versions("1.10.1", "b6193759a855ee8700f9494c1f08a24a600b59a7")

    -- Cargo builds a cdylib and a staticlib at once and upstream installs both, so linking
    -- always picks the shared object.
    add_configs("shared", {description = "Build shared library.", default = true, type = "boolean", readonly = true})

    add_deps("cmake")

    on_load(function (package)
        if package:is_plat("windows") then
            package:add("defines", "ZENOHC_DYN_LIB")
        end
    end)

    on_install("linux", "macosx", function (package)
        import("lib.detect.find_program")
        assert(find_program("cargo"), "cargo not found: zenoh-c is written in Rust and needs a working Rust toolchain")

        -- zenoh-c depends on git hosted crates and cargo's built-in git transport fails with
        -- SSL errors on some networks, so let cargo fetch them through the git cli.
        os.setenv("CARGO_NET_GIT_FETCH_WITH_CLI", "true")

        -- tests and examples are added unconditionally when zenoh-c is the root project
        io.replace("CMakeLists.txt", "add_subdirectory(tests)", "", {plain = true})
        io.replace("CMakeLists.txt", "add_subdirectory(examples)", "", {plain = true})

        local configs = {
            -- keep the cargo build out of the downloaded source tree
            "-DZENOHC_BUILD_IN_SOURCE_TREE=OFF",
            "-DZENOHC_TREAT_WARNING_AS_ERROR=OFF",
        }
        import("package.tools.cmake").install(package, configs)
    end)

    on_test(function (package)
        assert(package:check_csnippets({test = [[
            #include <zenoh.h>
            void test() {
                z_owned_config_t config;
                z_config_default(&config);
            }
        ]]}, {configs = {languages = "c11"}}))
    end)
package_end()
