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
            if not os.isfile(path.join(sourcedir, "thirdparty", "imgui", "imgui.cpp")) then
                os.vrunv("git", {"submodule", "update", "--init", "--recursive"}, {curdir = sourcedir})
            end
        end

        -- Patch CMakeLists.txt to always create glm::glm target
        local cmakelists = path.join(sourcedir, "CMakeLists.txt")
        if os.isfile(cmakelists) then
            -- Check if the patch is already applied
            local cl_content = io.readfile(cmakelists)
            if cl_content and cl_content:find("if(NOT TARGET glm::glm)") == nil then
                -- Read the original content and add target creation before target_link_libraries
                -- iridescence's CMakeLists.txt has: target_link_libraries(iridescence PRIVATE glm::glm ...)
                -- FindGLM.cmake doesn't create glm::glm when glm_FOUND=ON
                -- So we need to add a target creation before the link
                local patched = cl_content:gsub(
                    "(target_link_libraries%(iridescence PRIVATE)",
                    "if(NOT TARGET glm::glm)\n  add_library(glm::glm INTERFACE IMPORTED GLOBAL)\n  set_target_properties(glm::glm PROPERTIES\n    INTERFACE_INCLUDE_DIRECTORIES \"${GLM_INCLUDE_DIR}\")\nendif()\n%1"
                )
                io.writefile(cmakelists, patched)
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
