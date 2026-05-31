package("iridescence")
    set_homepage("https://github.com/koide3/iridescence")
    set_description("GLSL-based point cloud visualization and multi-sensor calibration library")
    set_license("MIT")

    add_urls("https://github.com/koide3/iridescence.git")

    add_versions("1.0.1", "b4e99f223f81f30a7e1b206eb2edf912af28e7e2")

    add_deps("cmake", "opengl", "glfw", "glm", "eigen")
    add_deps("libpng", "libjpeg-turbo")

    on_install(function (package)
        local configs = {
            "-DBUILD_EXAMPLES=OFF",
            "-DBUILD_PYTHON_BINDINGS=OFF",
            "-DBUILD_EXT_TESTS=OFF",
            "-DBUILD_WITH_MARCH_NATIVE=OFF",
            "-DCMAKE_POSITION_INDEPENDENT_CODE=ON",
            "-DCMAKE_WINDOWS_EXPORT_ALL_SYMBOLS=ON",
        }
        if package:config("shared") then
            table.insert(configs, "-DBUILD_SHARED_LIBS=ON")
        else
            table.insert(configs, "-DBUILD_SHARED_LIBS=OFF")
        end
        if package:is_plat("windows") then
            table.insert(configs, "-DCMAKE_CXX_FLAGS=/DNOMINMAX /D_USE_MATH_DEFINES /source-charset:utf-8")
        end
        -- Force glm_FOUND so iridescence skips FetchContent download
        local glm = package:dep("glm")
        if glm then
            table.insert(configs, "-Dglm_DIR=" .. glm:installdir())
            table.insert(configs, "-DGLM_DIR=" .. glm:installdir())
            table.insert(configs, "-Dglm_FOUND=ON")
        end
        import("package.tools.cmake").install(package, configs)
    end)

    on_test(function (package)
        assert(package:check_cxxsnippets({test = [[
            #include <glk/colormap.hpp>
            void test() {
                auto cmap = glk::Colormap::create(glk::Colormap::TURBO);
            }
        ]]}))
    end)
package_end()