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
            "-DCMAKE_WINDOWS_EXPORT_ALL_SYMBOLS=ON",
        }
        if package:config("shared") then
            table.insert(configs, "-DBUILD_SHARED_LIBS=ON")
        else
            table.insert(configs, "-DBUILD_SHARED_LIBS=OFF")
        end
        if package:is_plat("windows") then
            table.insert(configs, "-DCMAKE_CXX_FLAGS=/DNOMINMAX /D_USE_MATH_DEFINES /source-charset:utf-8")
        else
            table.insert(configs, "-DCMAKE_POSITION_INDEPENDENT_CODE=ON")
        end

        -- Prevent FetchContent downloads by pre-setting *_FOUND variables
        -- iridescence's CMakeLists.txt checks: glm_FOUND, glfw3_FOUND, Eigen3_FOUND
        -- If any is not found, it downloads from GitHub (which is unreliable in CN)
        local glm = package:dep("glm")
        if glm then
            table.insert(configs, "-DGLM_ROOT_DIR=" .. glm:installdir())
            table.insert(configs, "-Dglm_FOUND=ON")
            -- Also create glm::glm imported target that iridescence links against
            table.insert(configs, "-DGLM_INCLUDE_DIR=" .. path.join(glm:installdir(), "include"))
        end
        local glfw = package:dep("glfw")
        if glfw then
            table.insert(configs, "-Dglfw3_FOUND=ON")
        end
        local eigen = package:dep("eigen")
        if eigen then
            table.insert(configs, "-DEigen3_FOUND=ON")
        end

        import("package.tools.cmake").install(package, configs)

        -- iridescence installs headers under include/iridescence/ (e.g. include/iridescence/glk/)
        -- Move them up so #include <glk/...> resolves correctly
        local inc_irid = path.join(package:installdir(), "include", "iridescence")
        if os.isdir(inc_irid) then
            local inc_dir = path.join(package:installdir(), "include")
            for _, f in ipairs(os.files(path.join(inc_irid, "*"))) do
                os.mv(f, path.join(inc_dir, path.filename(f)))
            end
            for _, d in ipairs(os.dirs(path.join(inc_irid, "*"))) do
                os.mv(d, path.join(inc_dir, path.filename(d)))
            end
            os.rmdir(inc_irid)
        end
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