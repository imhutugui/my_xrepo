package("iridescence")
    set_homepage("https://github.com/koide3/iridescence")
    set_description("GLSL-based point cloud visualization and multi-sensor calibration library (patched)")
    set_license("MIT")

    add_urls("https://github.com/koide3/iridescence.git")

    add_versions("1.0.1-patched", "a3d11ffe9fc01c216856aa3b40396b1d8fd64b05")

    add_deps("cmake", "opengl", "glfw", "glm", "eigen")
    add_deps("libpng", "libjpeg-turbo")

    on_install(function (package)
        local glm = package:dep("glm")
        local sourcedir = path.join(package:cachedir(), "source", "iridescence")

        -- Ensure cmake/ directory exists and iridescence-config.cmake.in is present
        local cmake_dir = path.join(sourcedir, "cmake")
        if not os.isdir(cmake_dir) then
            os.mkdir(cmake_dir)
        end

        local cmake_in = path.join(cmake_dir, "iridescence-config.cmake.in")
        if not os.isfile(cmake_in) then
            -- Create a simple iridescence-config.cmake.in
            local cmake_in_content = [[
@PACKAGE_INIT@

include(CMakeFindDependencyMacro)
find_dependency(glm REQUIRED)
find_dependency(glfw3 REQUIRED)
find_dependency(Eigen3 REQUIRED)

include("${CMAKE_CURRENT_LIST_DIR}/iridescence-targets.cmake")

check_required_components(iridescence)
]]
            io.writefile(cmake_in, cmake_in_content)
            print("DEBUG: Created iridescence-config.cmake.in")
        end

        -- Patch CMakeLists.txt for glm_FOUND and glm::glm target
        local cl = io.readfile(path.join(sourcedir, "CMakeLists.txt"))
        if cl then
            if not cl:find("glm_FOUND ON") then
                cl = cl:gsub("find_package%(glm%)", [[if(NOT DEFINED GLM_INCLUDE_DIR AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/glm")
  set(GLM_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/glm")
endif()
set(glm_FOUND ON CACHE BOOL "Prevent download" FORCE)
find_package(glm)
if(NOT TARGET glm::glm)
  add_library(glm::glm INTERFACE IMPORTED)
  set_target_properties(glm::glm PROPERTIES INTERFACE_INCLUDE_DIRECTORIES "${GLM_INCLUDE_DIR}")
endif()]])
                io.writefile(path.join(sourcedir, "CMakeLists.txt"), cl)
                print("DEBUG: Patched CMakeLists.txt for glm_FOUND and glm::glm")
            end
        end

        -- Fix FetchContent blocks for glfw3 and Eigen3 using balanced parens matching
        cl = io.readfile(path.join(sourcedir, "CMakeLists.txt"))
        if cl then
            local function replace_if_block(cl, search_key, replacement)
                local key_start = cl:find(search_key)
                if key_start then
                    local depth = 0
                    local endif_pos = 0
                    for i = key_start, #cl do
                        local c = cl:sub(i, i)
                        if c == "(" then depth = depth + 1 end
                        if c == ")" then
                            depth = depth - 1
                            if depth == 0 then
                                endif_pos = i + 1
                                break
                            end
                        end
                    end
                    if endif_pos > 0 then
                        local before = cl:sub(1, endif_pos)
                        local after = cl:sub(endif_pos + 1)
                        cl = before .. "  message(STATUS \"Using system " .. search_key:sub(9, -8) .. "\")\n" .. after
                    end
                end
                return cl
            end

            cl = replace_if_block(cl, "if(NOT glfw3_FOUND)", "Using system GLFW3")
            cl = replace_if_block(cl, "if(NOT Eigen3_FOUND)", "Using system Eigen3")
            io.writefile(path.join(sourcedir, "CMakeLists.txt"), cl)
        end

        -- Patch implot_items.cpp
        local imp = path.join(sourcedir, "thirdparty", "implot", "implot_items.cpp")
        if os.isfile(imp) then
            local im = io.readfile(imp)
            if im and im:find("AddConcavePolyFilled") then
                im = im:gsub("AddConcavePolyFilled", "AddConvexPolyFilled")
                io.writefile(imp, im)
                print("DEBUG: Patched implot_items.cpp")
            end
        end

        -- Build configuration: use dynamic library by default via BUILD_SHARED_LIBS
        local configs = {
            "-DBUILD_EXAMPLES:BOOL=OFF",
            "-DBUILD_PYTHON_BINDINGS:BOOL=OFF",
            "-DBUILD_EXT_TESTS:BOOL=OFF",
            "-DBUILD_WITH_MARCH_NATIVE:BOOL=OFF",
            "-DCMAKE_WINDOWS_EXPORT_ALL_SYMBOLS:BOOL=ON",
            "-Dglfw3_FOUND:BOOL=ON",
            "-DEigen3_FOUND:BOOL=ON",
        }
        
        -- Enable shared library building if package:config("shared") is true
        if package:config("shared") then
            table.insert(configs, "-DBUILD_SHARED_LIBS:BOOL=ON")
        else
            table.insert(configs, "-DBUILD_SHARED_LIBS:BOOL=OFF")
        end
        
        if glm then
            table.insert(configs, "-DGLM_ROOT_DIR=" .. glm:installdir())
            table.insert(configs, "-DGLM_INCLUDE_DIR=" .. path.join(glm:installdir(), "include"))
        end

        import("package.tools.cmake").install(package, {
            configs = configs,
            cxxflags = "/DNOMINMAX /D_USE_MATH_DEFINES /EHsc /source-charset:utf-8",
        })

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
        -- no test
    end)
package_end()
