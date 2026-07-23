package("glim")
    set_homepage("https://github.com/koide3/glim")
    set_description("GPU-accelerated Lidar-Inertial odometry and Mapping framework")
    set_license("MIT")

    add_urls("https://github.com/koide3/glim.git")

    add_versions("v1.1.0", "65a5562c6b8906e60693c63cc0c95de885426352")

    add_deps("cmake", "gtsam 4.2.2", "gtsam_points 1.2.2", "eigen")
    add_deps("boost", {configs = {serialization = true}})
    add_deps("spdlog")

    on_load(function (package)
        if not package:is_plat("windows") then
            package:add("deps", "tbb")
        end
    end)

    on_install(function (package)
        local sourcedir = path.join(package:cachedir(), "source", "glim")

        -- Helper: safe file I/O
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

        -- Patch CMakeLists.txt to disable CUDA, viewer, OpenCV, and march-native
        local cmake = path.join(sourcedir, "CMakeLists.txt")
        local cl = read_text(cmake)
        if cl then
            if not string.find(cl, "GLIM_PATCHED", 1, true) then
                local patched = cl

                -- Change project version to match xmake version
                patched = patched:gsub(
                    "project%(glim VERSION [^ ]+",
                    "project(glim VERSION 1.1.0"
                )

                -- Force options to OFF before the option() commands
                -- This prevents cmake from overriding our -D flags
                patched = patched:gsub(
                    "option%(BUILD_WITH_CUDA ",
                    "set(BUILD_WITH_CUDA OFF CACHE BOOL \"\" FORCE)\noption(BUILD_WITH_CUDA "
                )
                patched = patched:gsub(
                    "option%(BUILD_WITH_VIEWER ",
                    "set(BUILD_WITH_VIEWER OFF CACHE BOOL \"\" FORCE)\noption(BUILD_WITH_VIEWER "
                )
                patched = patched:gsub(
                    "option%(BUILD_WITH_OPENCV ",
                    "set(BUILD_WITH_OPENCV OFF CACHE BOOL \"\" FORCE)\noption(BUILD_WITH_OPENCV "
                )
                patched = patched:gsub(
                    "option%(BUILD_WITH_MARCH_NATIVE ",
                    "set(BUILD_WITH_MARCH_NATIVE OFF CACHE BOOL \"\" FORCE)\noption(BUILD_WITH_MARCH_NATIVE "
                )

                -- Fix C++ standard flag for MSVC (use /std:c++17 instead of -std=c++17)
                patched = patched:gsub("add_compile_options%(%-std=c%+%+17%)", "if(MSVC)\n  add_compile_options(/std:c++17 /utf-8 /DNOMINMAX /D_USE_MATH_DEFINES /bigobj /DWIN32_LEAN_AND_MEAN)\n  set(CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS ON)\nelse()\n  add_compile_options(-std=c++17)\nendif()")

                -- Fix spdlog find_package to handle header-only library
                patched = patched:gsub(
                    "find_package%(spdlog REQUIRED%)",
                    [[find_package(spdlog QUIET)
if(NOT spdlog_FOUND)
  find_path(SPDLOG_INCLUDE_DIR spdlog/spdlog.h)
  if(SPDLOG_INCLUDE_DIR)
    set(spdlog_FOUND TRUE)
    add_library(spdlog::spdlog INTERFACE IMPORTED)
    set_target_properties(spdlog::spdlog PROPERTIES
      INTERFACE_INCLUDE_DIRECTORIES "${SPDLOG_INCLUDE_DIR}"
    )
    message(STATUS "Found spdlog (header-only) at: ${SPDLOG_INCLUDE_DIR}")
  else()
    message(FATAL_ERROR "Could not find spdlog")
  endif()
endif()]]
                )

                -- Add GLIM_PATCHED marker at the end
                patched = patched .. "\nset(GLIM_PATCHED TRUE)\n"

                write_text(cmake, patched)
                print("DEBUG: Patched CMakeLists.txt")
            end
        end

        -- Patch for MSVC: add missing #include <string> in load_module.hpp
        local load_module_hpp = path.join(sourcedir, "include/glim/util/load_module.hpp")
        local lm_content = read_text(load_module_hpp)
        if lm_content and not string.find(lm_content, "#include <string>", 1, true) then
            lm_content = lm_content:gsub("#pragma once\n", "#pragma once\n#include <string>\n")
            write_text(load_module_hpp, lm_content)
            print("DEBUG: Added #include <string> to load_module.hpp")
        end

        -- Patch for MSVC: add missing #include <string> in extension_module.hpp
        local ext_module_hpp = path.join(sourcedir, "include/glim/util/extension_module.hpp")
        local em_content = read_text(ext_module_hpp)
        if em_content and not string.find(em_content, "#include <string>", 1, true) then
            em_content = em_content:gsub("#pragma once\n", "#pragma once\n#include <string>\n")
            write_text(ext_module_hpp, em_content)
            print("DEBUG: Added #include <string> to extension_module.hpp")
        end

        -- Patch for MSVC: fix GTSAM ERROR macro conflict
        -- Windows wingdi.h defines ERROR=0 which conflicts with gtsam::IterativeOptimizationParameters::ERROR
        -- Add #undef ERROR to all glim source files that include GTSAM headers
        local gtsam_source_dirs = {
            "src/glim/odometry",
            "src/glim/mapping",
            "src/glim/common",
            "src/glim/preprocess",
            "include/glim/odometry",
            "include/glim/mapping",
            "include/glim/common",
        }
        for _, dir in ipairs(gtsam_source_dirs) do
            local full_dir = path.join(sourcedir, dir)
            local files = os.isdir(full_dir) and os.files(path.join(full_dir, "*.hpp")) or {}
            local files2 = os.isdir(full_dir) and os.files(path.join(full_dir, "*.cpp")) or {}
            for _, f in ipairs(files) do
                local content = read_text(f)
                if content and string.find(content, "gtsam/", 1, true) and not string.find(content, "#undef ERROR", 1, true) then
                    content = content:gsub("(#include <gtsam/[^>]+>)", "%1\n#ifdef ERROR\n#undef ERROR\n#endif")
                    write_text(f, content)
                end
            end
            for _, f in ipairs(files2) do
                local content = read_text(f)
                if content and string.find(content, "gtsam/", 1, true) and not string.find(content, "#undef ERROR", 1, true) then
                    content = content:gsub("(#include <gtsam/[^>]+>)", "%1\n#ifdef ERROR\n#undef ERROR\n#endif")
                    write_text(f, content)
                end
            end
        end
        print("DEBUG: Added #undef ERROR to GTSAM headers")

        -- Patch for MSVC: fix fmt include path (spdlog bundles fmt in spdlog/fmt/bundled/)
        local convert_hpp = path.join(sourcedir, "include/glim/util/convert_to_string.hpp")
        local cv_content = read_text(convert_hpp)
        if cv_content and string.find(cv_content, '#include <fmt/format.h>', 1, true) then
            cv_content = cv_content:gsub('#include <fmt/format.h>', '#include <spdlog/fmt/bundled/format.h>')
            write_text(convert_hpp, cv_content)
            print("DEBUG: Fixed fmt include path in convert_to_string.hpp")
        end

        -- Also fix fmt include in map_cell.cpp
        local map_cell_cpp = path.join(sourcedir, "src/glim/viewer/editor/map_cell.cpp")
        local mc_content = read_text(map_cell_cpp)
        if mc_content and string.find(mc_content, '#include <fmt/format.h>', 1, true) then
            mc_content = mc_content:gsub('#include <fmt/format.h>', '#include <spdlog/fmt/bundled/format.h>')
            write_text(map_cell_cpp, mc_content)
            print("DEBUG: Fixed fmt include path in map_cell.cpp")
        end

        -- Fix fmt::ptr usage with shared_ptr (need .get() for raw pointer)
        local function fix_fmt_ptr(filepath)
            local content = read_text(filepath)
            if content and string.find(content, 'fmt::ptr(', 1, true) then
                -- Replace fmt::ptr(xxx) with fmt::ptr(xxx.get()) for shared_ptr
                local new_content = content:gsub('fmt::ptr%(([^%)]+)%)', 'fmt::ptr(%1.get())')
                if new_content ~= content then
                    write_text(filepath, new_content)
                    print("DEBUG: Fixed fmt::ptr usage in " .. filepath)
                end
            end
        end
        fix_fmt_ptr(path.join(sourcedir, "src/glim/odometry/odometry_estimation_ct.cpp"))
        fix_fmt_ptr(path.join(sourcedir, "src/glim/odometry/odometry_estimation_cpu.cpp"))

        -- Patch for MSVC: fix struct/class forward declaration mismatches
        -- gtsam_points defines LevenbergMarquardtOptimizationStatus and ISAM2ResultExt as struct,
        -- but glim forward-declares them as class. MSVC mangles struct/class differently (U vs V),
        -- causing linker errors.
        local data_validator_hpp = path.join(sourcedir, "include/glim/util/data_validator.hpp")
        local dv_content = read_text(data_validator_hpp)
        if dv_content and string.find(dv_content, "class RawPoints;", 1, true) then
            dv_content = dv_content:gsub("class RawPoints;", "struct RawPoints;")
            write_text(data_validator_hpp, dv_content)
            print("DEBUG: Fixed class RawPoints -> struct RawPoints in data_validator.hpp")
        end

        local callbacks_hpp = path.join(sourcedir, "include/glim/mapping/callbacks.hpp")
        local cb_content = read_text(callbacks_hpp)
        if cb_content then
            local changed = false
            if string.find(cb_content, "class ISAM2ResultExt;", 1, true) then
                cb_content = cb_content:gsub("class ISAM2ResultExt;", "struct ISAM2ResultExt;")
                changed = true
            end
            if string.find(cb_content, "class LevenbergMarquardtOptimizationStatus;", 1, true) then
                cb_content = cb_content:gsub("class LevenbergMarquardtOptimizationStatus;", "struct LevenbergMarquardtOptimizationStatus;")
                changed = true
            end
            if changed then
                write_text(callbacks_hpp, cb_content)
                print("DEBUG: Fixed struct/class mismatches in callbacks.hpp")
            end
        end

        -- Patch for MSVC: replace dlfcn.h with Windows LoadLibrary/GetProcAddress
        local load_module_cpp = path.join(sourcedir, "src/glim/util/load_module.cpp")
        local lmc_content = read_text(load_module_cpp)
        if lmc_content and string.find(lmc_content, "#include <dlfcn.h>", 1, true) then
            local win_load_module = [[#include <glim/util/load_module.hpp>

#include <spdlog/spdlog.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <dlfcn.h>
#endif

namespace glim {

void open_so(const std::string& so_name) {
#ifdef _WIN32
  HMODULE handle = LoadLibraryA(so_name.c_str());
  if (handle == nullptr) {
    spdlog::warn("failed to open {}", so_name);
  }
#else
  void* handle = dlopen(so_name.c_str(), RTLD_LAZY);
  if (handle == nullptr) {
    spdlog::warn("failed to open {}", so_name);
    spdlog::warn("{}", dlerror());
  }
#endif
}

void* load_symbol(const std::string& so_name, const std::string& symbol_name) {
#ifdef _WIN32
  HMODULE handle = LoadLibraryA(so_name.c_str());
  if (handle == nullptr) {
    spdlog::warn("failed to open {}", so_name);
    return nullptr;
  }

  auto* func = (void*)GetProcAddress(handle, symbol_name.c_str());
  if (func == nullptr) {
    spdlog::warn("failed to find symbol={} in {}", symbol_name, so_name);
  }

  return func;
#else
  void* handle = dlopen(so_name.c_str(), RTLD_LAZY);
  if (handle == nullptr) {
    spdlog::warn("failed to open {}", so_name);
    spdlog::warn("{}", dlerror());
    return nullptr;
  }

  auto* func = dlsym(handle, symbol_name.c_str());
  if (func == nullptr) {
    spdlog::warn("failed to find symbol={} in {}", symbol_name, so_name);
    spdlog::warn("{}", dlerror());
  }

  return func;
#endif
}

}  // namespace glim
]]
            write_text(load_module_cpp, win_load_module)
            print("DEBUG: Patched load_module.cpp for Windows")
        end

        -- Patch for MSVC: replace size_t with int in OpenMP loops
        local function patch_openmp_size_t(dir)
            local files = os.isdir(dir) and os.files(path.join(dir, "*.hpp")) or {}
            local files2 = os.isdir(dir) and os.files(path.join(dir, "*.cpp")) or {}
            local total = 0
            for _, f in ipairs(files) do
                local content = read_text(f)
                if content then
                    local new_content, n = string.gsub(content, "for %(size_t", "for (int")
                    if n > 0 then
                        write_text(f, new_content)
                        print("DEBUG: Patched " .. f .. " (size_t->int, " .. n .. " occurrences)")
                        total = total + n
                    end
                end
            end
            for _, f in ipairs(files2) do
                local content = read_text(f)
                if content then
                    local new_content, n = string.gsub(content, "for %(size_t", "for (int")
                    if n > 0 then
                        write_text(f, new_content)
                        print("DEBUG: Patched " .. f .. " (size_t->int, " .. n .. " occurrences)")
                        total = total + n
                    end
                end
            end
            return total
        end

        -- Patch source directories for MSVC OpenMP
        local patch_dirs = {
            "src/glim/util",
            "src/glim/preprocess",
            "src/glim/common",
            "src/glim/odometry",
            "src/glim/mapping",
            "src/glim/viewer",
            "include/glim/util",
            "include/glim/common",
            "include/glim/odometry",
            "include/glim/mapping",
        }
        local total_patches = 0
        for _, dir in ipairs(patch_dirs) do
            local full_dir = path.join(sourcedir, dir)
            total_patches = total_patches + patch_openmp_size_t(full_dir)
        end
        print("DEBUG: Total size_t->int patches applied: " .. total_patches)

        -- Build with xmake/cmake
        local configs = {
            "-DBUILD_WITH_CUDA=OFF",
            "-DBUILD_WITH_CUDA_MULTIARCH=OFF",
            "-DBUILD_WITH_MARCH_NATIVE=OFF",
            "-DBUILD_WITH_VIEWER=OFF",
            "-DBUILD_WITH_OPENCV=OFF",
            "-DCMAKE_CXX_FLAGS=/utf-8 /DNOMINMAX /D_USE_MATH_DEFINES",
        }

        if package:is_plat("windows") then
            table.insert(configs, "-DCMAKE_POSITION_INDEPENDENT_CODE=OFF")
        else
            table.insert(configs, "-DCMAKE_POSITION_INDEPENDENT_CODE=ON")
        end

        import("package.tools.cmake").install(package, {
            configs = configs,
        })
    end)

    on_test(function (package)
        assert(package:check_cxxsnippets({test = [[
            #include <glim/util/raw_points.hpp>
            void test() {
                glim::RawPoints::Ptr p = std::make_shared<glim::RawPoints>();
                p->stamp = 0.0;
            }
        ]]}, {configs = {languages = "c++17"}}))
    end)
package_end()
