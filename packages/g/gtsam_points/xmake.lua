package("gtsam_points")
    set_homepage("https://github.com/koide3/gtsam_points")
    set_description("A collection of GTSAM factors and optimizers for point cloud SLAM")
    set_license("MIT")

    add_urls("https://github.com/koide3/gtsam_points.git")

    add_versions("v1.2.1", "620ad2786833601c81453eb7ad09a24d4331063a")

    add_deps("cmake", "gtsam 4.2.2", "eigen")
    add_deps("boost", {configs = {graph = true, filesystem = true}})

    on_load(function (package)
        if not package:is_plat("windows") then
            package:add("deps", "tbb")
        end
    end)

    on_install(function (package)
        local sourcedir = path.join(package:cachedir(), "source", "gtsam_points")
        print("DEBUG on_install: sourcedir=" .. sourcedir)

        -- Helper: safe file I/O (use io.open to avoid os.writefile which is nil in xrepo sandbox)
        local function write_text(filepath, content)
            local f = io.open(filepath, "w")
            if not f then
                print("ERROR: Cannot write " .. filepath)
                return false
            end
            f:write(content)
            f:close()
            return true
        end
        local function read_text(filepath)
            local f = io.open(filepath, "r")
            if not f then return nil end
            local content = f:read("*a")
            f:close()
            return content
        end

        -- IMPORTANT: string.gsub uses Lua pattern matching (NOT plain string match)!
        -- Lua pattern special chars: . % + * - ? [ ] ^ $ ( )
        -- Use this function to escape them for literal matching:
        local function lpat(s)
            return string.gsub(s, '[.%%+%*%-?%[%]^%$%(%)]', '%%%1')
        end

        -- Patch 1: CMakeLists.txt - add _USE_MATH_DEFINES via target_compile_definitions
        local cmake = path.join(sourcedir, "CMakeLists.txt")
        local cl = read_text(cmake)
        if cl then
            if not string.find(cl, "_USE_MATH_DEFINES", 1, true) then
                local idx = string.find(cl, "add_library(gtsam_points SHARED", 1, true)
                if idx then
                    local depth = 0
                    local endpos = 0
                    for i = idx, #cl do
                        local c = cl:sub(i, i)
                        if c == "(" then depth = depth + 1 end
                        if c == ")" then
                            depth = depth - 1
                            if depth == 0 then
                                endpos = i
                                break
                            end
                        end
                    end
                    if endpos > 0 then
                        local patched = cl:sub(1, endpos) ..
                            '\ntarget_compile_definitions(gtsam_points PRIVATE _USE_MATH_DEFINES)\ntarget_compile_options(gtsam_points PRIVATE /DNOMINMAX)\n' ..
                            cl:sub(endpos + 1)
                        write_text(cmake, patched)
                        print("DEBUG: Patched CMakeLists.txt")
                    else
                        print("DEBUG: Could not find add_library closing paren")
                    end
                else
                    print("DEBUG: add_library not found")
                end
            else
                print("DEBUG: CMakeLists.txt already has _USE_MATH_DEFINES")
            end
        else
            print("DEBUG: Could not read CMakeLists.txt")
        end

        -- Patch 2: M_PI in header files
        local headers = {
            "include/gtsam_points/segmentation/region_growing.hpp",
            "include/gtsam_points/registration/ransac.hpp",
            "include/gtsam_points/segmentation/min_cut.hpp",
        }
        for _, rel in ipairs(headers) do
            local fpath = path.join(sourcedir, rel)
            local content = read_text(fpath)
            if content then
                if not string.find(content, "ifndef M_PI", 1, true) then
                    content = content:gsub(lpat("#pragma once"), "#pragma once\n#ifndef M_PI\n#define M_PI 3.14159265358979323846\n#endif\n", 1)
                    write_text(fpath, content)
                    print("DEBUG: Patched M_PI in " .. rel)
                else
                    print("DEBUG: " .. rel .. " already has M_PI")
                end
            end
        end


        -- Patch 4: point_cloud_cpu.cpp - fix regex_search with rvalue
        local pcc = path.join(sourcedir, "src/gtsam_points/types/point_cloud_cpu.cpp")
        local pcc_content = read_text(pcc)
        if pcc_content then
            local old_pattern = lpat("    if (!std::regex_search(itr->path().string(), matched, aux_name_regex))")
            local new_line = "    std::string _aux_filename = itr->path().string();\n    if (!std::regex_search(_aux_filename, matched, aux_name_regex))"
            local new_content, n = string.gsub(pcc_content, old_pattern, new_line)
            print("DEBUG: point_cloud_cpu.cpp gsub returned n=" .. tostring(n))
            if n and n > 0 then
                write_text(pcc, new_content)
                print("DEBUG: Patched point_cloud_cpu.cpp")
            else
                print("DEBUG: point_cloud_cpu.cpp gsub found " .. tostring(n) .. " matches")
            end
        end

        -- Patch 5b: gaussian_voxelmap_cpu_funcs.cpp - add #include <numeric> for std::accumulate
        local gaussian_voxel = path.join(sourcedir, "src/gtsam_points/types/gaussian_voxelmap_cpu_funcs.cpp")
        local gv_content = read_text(gaussian_voxel)
        if gv_content then
            if not string.find(gv_content, "#include <numeric>", 1, true) then
                -- Find first #include line and add after it
                local include_idx = string.find(gv_content, "#include", 1, true)
                if include_idx then
                    -- Find end of this line
                    local newline_idx = string.find(gv_content, "\n", include_idx)
                    if newline_idx then
                        gv_content = gv_content:sub(1, newline_idx) .. "#include <numeric>\n" .. gv_content:sub(newline_idx + 1)
                        write_text(gaussian_voxel, gv_content)
                        print("DEBUG: Added #include <numeric> to gaussian_voxelmap_cpu_funcs.cpp")
                    end
                end
            end
        end

        -- Patch 5c: fpfh_estimation.cpp - fix constexpr int BINS not being treated as compile-time constant by MSVC
        -- Change "constexpr int BINS = 11" to "enum { BINS = 11 }"
        local fpfh_src = path.join(sourcedir, "src/gtsam_points/features/fpfh_estimation.cpp")
        local fpfh_src_content = read_text(fpfh_src)
        if fpfh_src_content then
            local new_fpfh, n = string.gsub(fpfh_src_content, lpat("constexpr int BINS = 11"), "enum { BINS = 11 }")
            if n > 0 then
                write_text(fpfh_src, new_fpfh)
                print("DEBUG: Changed constexpr int BINS = 11 to enum { BINS = 11 } in fpfh_estimation.cpp")
            end
        end

        -- Patch 5: fast_occupancy_grid.cpp - remove default arguments from explicit template instantiations
        local foo = path.join(sourcedir, "src/gtsam_points/ann/fast_occupancy_grid.cpp")
        local foo_content = read_text(foo)
        if foo_content then
            local patched = false
            local new_foo, n1 = string.gsub(foo_content, lpat("= Eigen::Isometry3d::Identity()"), "")
            if n1 > 0 then
                print("DEBUG: Removed " .. n1 .. " Eigen::Isometry3d::Identity defaults")
                foo_content = new_foo
                patched = true
            end
            local new_foo2, n2 = string.gsub(foo_content, lpat("= gtsam::Pose3()"), "")
            if n2 > 0 then
                print("DEBUG: Removed " .. n2 .. " gtsam::Pose3 defaults")
                foo_content = new_foo2
                patched = true
            end
            if patched then
                write_text(foo, foo_content)
                print("DEBUG: Patched fast_occupancy_grid.cpp")
            else
                print("DEBUG: fast_occupancy_grid.cpp checked")
            end
        end

        -- Patch 6: ALL files with OpenMP loops - replace ALL occurrences of "for (size_t" with "for (int"
        -- This is a global fix because MSVC OpenMP requires signed integral type for loop index
        -- We patch ALL .hpp and .cpp files in the source tree
        local function patch_all_sources()
            local target_dirs = {
                "include/gtsam_points/segmentation",
                "include/gtsam_points/segmentation/impl",
                "include/gtsam_points/registration",
                "include/gtsam_points/registration/impl",
                "include/gtsam_points/features",
                "include/gtsam_points/alignment",
                "include/gtsam_points/registration",
                "src/gtsam_points/segmentation",
                "src/gtsam_points/registration",
                "src/gtsam_points/features",
                "src/gtsam_points/types",
                "src/gtsam_points/alignment",
                "src/gtsam_points/ann",
            }
            local total = 0
            for _, rel in ipairs(target_dirs) do
                local dir = path.join(sourcedir, rel)
                local files = os.isdir(dir) and os.files(path.join(dir, "*.hpp")) or {}
                local files2 = os.isdir(dir) and os.files(path.join(dir, "*.cpp")) or {}
                for _, f in ipairs(files) do
                    local content = read_text(f)
                    if content then
                        local new_content, n = string.gsub(content, lpat("for (size_t"), "for (int")
                        if n > 0 then
                            write_text(f, new_content)
                            print("DEBUG: Patched " .. f:gsub(sourcedir .. "\\", "") .. " (size_t->int, " .. n .. " occurrences)")
                            total = total + n
                        end
                    end
                end
                for _, f in ipairs(files2) do
                    local content = read_text(f)
                    if content then
                        local new_content, n = string.gsub(content, lpat("for (size_t"), "for (int")
                        if n > 0 then
                            write_text(f, new_content)
                            print("DEBUG: Patched " .. f:gsub(sourcedir .. "\\", "") .. " (size_t->int, " .. n .. " occurrences)")
                            total = total + n
                        end
                    end
                end
            end
            print("DEBUG: Total size_t->int patches applied: " .. total)
        end
        patch_all_sources()

        -- Build with xmake/cmake
        local configs = {
            "-DBUILD_TESTS=OFF",
            "-DBUILD_DEMO=OFF",
            "-DBUILD_EXAMPLE=OFF",
            "-DBUILD_TOOLS=OFF",
            "-DBUILD_WITH_MARCH_NATIVE=OFF",
            "-DBUILD_WITH_CUDA=OFF",
        }
        if package:config("shared") then
            table.insert(configs, "-DBUILD_SHARED_LIBS=ON")
        else
            table.insert(configs, "-DBUILD_SHARED_LIBS=OFF")
            if not package:is_plat("windows") then
                table.insert(configs, "-DCMAKE_POSITION_INDEPENDENT_CODE=ON")
            end
        end
        if package:is_plat("windows") then
            table.insert(configs, "-DBUILD_WITH_TBB=OFF")
            table.insert(configs, "-DBUILD_WITH_OPENMP=OFF")
            table.insert(configs, "-DCMAKE_POSITION_INDEPENDENT_CODE=OFF")
        else
            table.insert(configs, "-DBUILD_WITH_TBB=ON")
            table.insert(configs, "-DBUILD_WITH_OPENMP=ON")
        end

        -- Add compile definitions to xmake flags
        import("package.tools.cmake").install(package, {
            configs = configs,
            cxxflags = "/DNOMINMAX /D_USE_MATH_DEFINES /EHsc",
        })
    end)

    on_test(function (package)
        assert(package:check_cxxsnippets({test = [[
            #include <gtsam_points/types/point_cloud.hpp>
            void test() {
                gtsam_points::PointCloud cloud;
            }
        ]]}))
    end)
package_end()
