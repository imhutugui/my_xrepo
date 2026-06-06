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

        -- Patch 1: CMakeLists.txt - always create glm::glm target
        local cmakelists = path.join(sourcedir, "CMakeLists.txt")
        if os.isfile(cmakelists) then
            local cl_content = io.readfile(cmakelists)
            if cl_content and cl_content:find("if(NOT TARGET glm::glm)") == nil then
                local patched = cl_content:gsub(
                    "(target_link_libraries%(iridescence PRIVATE)",
                    "if(NOT TARGET glm::glm)\n  add_library(glm::glm INTERFACE IMPORTED GLOBAL)\n  set_target_properties(glm::glm PROPERTIES\n    INTERFACE_INCLUDE_DIRECTORIES \"${GLM_INCLUDE_DIR}\")\nendif()\n%1"
                )
                io.writefile(cmakelists, patched)
            end
        end

        -- Patch 2: implot_items.cpp - fix ImGui 1.89 compatibility
        -- AddConcavePolyFilled was added in ImGui 1.90, replace with AddPolyline + ClosePolygon
        local implot_items = path.join(sourcedir, "thirdparty", "implot", "implot_items.cpp")
        if os.isfile(implot_items) then
            local im_content = io.readfile(implot_items)
            if im_content and im_content:find("AddConcavePolyFilled") then
                im_content = im_content:gsub(
                    "draw_list[%w:]*AddConcavePolyFilled%(([^,]+), ([^,]+), ([^)]+)%)",
                    "draw_list:AddPolyline(%1, %2, %3)\n            draw_list:ClosePolygon()"
                )
                io.writefile(implot_items, im_content)
            end
        end

        -- Patch 3: region_growing.hpp - add #include <cmath> for M_PI on MSVC
        local rg_hpp = path.join(sourcedir, "include", "gtsam_points", "segmentation", "region_growing.hpp")
        if os.isfile(rg_hpp) then
            local rg_content = io.readfile(rg_hpp)
            if rg_content and not rg_content:find("#include.*cmath") then
                rg_content = rg_content:gsub(
                    "(#include <cmath>)",
                    "%1\n#include <limits>"
                )
                -- For MSVC, M_PI is not defined by cmath; add it
                rg_content = rg_content:gsub(
                    "(#include <cmath>)",
                    "%1\n#ifndef M_PI\n#define M_PI 3.14159265358979323846\n#endif"
                )
                io.writefile(rg_hpp, rg_content)
            end
        end

        -- Build configuration
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

        -- Move headers from include/iridescence/ to include/
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
