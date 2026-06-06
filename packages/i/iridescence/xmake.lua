package("iridescence")
    set_homepage("https://github.com/koide3/iridescence")
    set_description("GLSL-based point cloud visualization and multi-sensor calibration library (patched)")
    set_license("MIT")

    add_urls("https://github.com/koide3/iridescence.git")

    add_versions("1.0.1-patched", "a3d11ffe9fc01c216856aa3b40396b1d8fd64b05")

    add_deps("cmake", "opengl", "glfw", "glm", "eigen")
    add_deps("libpng", "libjpeg-turbo")

    on_install(function (package)
        local sourcedir = path.join(package:cachedir(), "source", "iridescence")
        if os.isfile(path.join(sourcedir, ".gitmodules")) then
            os.vrunv("git", {"submodule", "update", "--init", "--recursive"}, {curdir = sourcedir})
        end

        -- Remove .git to prevent xmake/cmake from resetting files
        local gitdir = path.join(sourcedir, ".git")
        if os.isdir(gitdir) then
            os.rm("-r", gitdir)
        end

        -- Patch 1: CMakeLists.txt - ensure glm::glm target is created
        local cmakelists = path.join(sourcedir, "CMakeLists.txt")
        if os.isfile(cmakelists) then
            local cl = io.readfile(cmakelists)
            if cl and cl:find("if(NOT glm_FOUND)") then
                cl = cl:gsub(
                    "if%(NOT glm_FOUND%).*endif%()",
                    "if(NOT TARGET glm::glm)\n" ..
                    "  add_library(glm::glm INTERFACE IMPORTED GLOBAL)\n" ..
                    "  set_target_properties(glm::glm PROPERTIES\n" ..
                    "    INTERFACE_INCLUDE_DIRECTORIES \"${GLM_ROOT_DIR}/include\" \"${GLM_INCLUDE_DIR}\")\n" ..
                    "endif()\n",
                    1
                )
                io.writefile(cmakelists, cl)
            end
        end

        -- Patch 2: implot_items.cpp - fix ImGui 1.89 compatibility
        local implot_items = path.join(sourcedir, "thirdparty", "implot", "implot_items.cpp")
        if os.isfile(implot_items) then
            local im = io.readfile(implot_items)
            if im and im:find("AddConcavePolyFilled") then
                im = im:gsub("AddConcavePolyFilled", "AddConvexPolyFilled", 1)
                io.writefile(implot_items, im)
            end
        end

        local configs = {
            "-DBUILD_EXAMPLES:BOOL=OFF",
            "-DBUILD_PYTHON_BINDINGS:BOOL=OFF",
            "-DBUILD_EXT_TESTS:BOOL=OFF",
            "-DBUILD_WITH_MARCH_NATIVE:BOOL=OFF",
            "-DCMAKE_WINDOWS_EXPORT_ALL_SYMBOLS:BOOL=ON",
        }
        if package:config("shared") then
            table.insert(configs, "-DBUILD_SHARED_LIBS:BOOL=ON")
        else
            table.insert(configs, "-DBUILD_SHARED_LIBS:BOOL=OFF")
        end
        if package:is_plat("windows") then
            table.insert(configs, "-DCMAKE_CXX_FLAGS=/DNOMINMAX /D_USE_MATH_DEFINES /EHsc /source-charset:utf-8")
        else
            table.insert(configs, "-DCMAKE_POSITION_INDEPENDENT_CODE:BOOL=ON")
        end

        local glm = package:dep("glm")
        if glm then
            table.insert(configs, "-DGLM_ROOT_DIR=" .. glm:installdir())
            table.insert(configs, "-Dglm_FOUND:BOOL=ON")
            table.insert(configs, "-DGLM_INCLUDE_DIR=" .. path.join(glm:installdir(), "include"))
        end
        local glfw = package:dep("glfw")
        if glfw then
            table.insert(configs, "-Dglfw3_FOUND:BOOL=ON")
        end
        local eigen = package:dep("eigen")
        if eigen then
            table.insert(configs, "-DEigen3_FOUND:BOOL=ON")
        end

        import("package.tools.cmake").install(package, configs)

        -- Move headers
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
