package("gtsam")
    set_homepage("https://github.com/borglab/gtsam")
    set_description("Georgia Tech Smoothing and Mapping library - factor graph optimization for SLAM and SFM")

    add_urls("https://github.com/borglab/gtsam.git")

    add_versions("4.2.0", "4f66a491ffc83cf092d0d818b11dc35135521612")
    add_versions("4.2.1", "0a070c2700fcf6fc7b960da8d734bbd02043c89a")
    add_versions("4.2.2", "35dd70360fb39c81081b8f420a4d72e0b896a96e")

    add_deps("cmake")
    add_deps("eigen 3.4.0")
    add_deps("boost", {configs = {serialization = true, filesystem = true, thread = true,
                                 program_options = true, date_time = true, timer = true,
                                 chrono = true, graph = true}})

    on_load(function (package)
        -- TBB is optional; skip on Windows due to build complexity
        if not package:is_plat("windows") then
            package:add("deps", "tbb")
        end

        if package:is_plat("windows") then
            -- GTSAM uses UnDecorateSymbolName from Dbghelp.lib in its demangle function.
            -- When built as a static library, the PRIVATE link in GTSAM's CMakeLists.txt
            -- doesn't propagate, so consumers need to link Dbghelp explicitly.
            package:add("syslinks", "dbghelp")
        end
    end)

    on_install("windows", "linux", "macosx", function (package)
        local configs = {}

        -- GTSAM CMake options (use :BOOL type prefix to override option() defaults)
        -- Without :BOOL, CMake option() treats the cache entry as UNINITIALIZED
        -- and overwrites it with its own default (OFF), causing version mismatch.
        table.insert(configs, "-DGTSAM_BUILD_TESTS:BOOL=OFF")
        table.insert(configs, "-DGTSAM_BUILD_EXAMPLES_ALWAYS:BOOL=OFF")
        table.insert(configs, "-DGTSAM_BUILD_UNSTABLE:OPTION=ON")
        table.insert(configs, "-DGTSAM_INSTALL_MATLAB_TOOLBOX:BOOL=OFF")
        table.insert(configs, "-DGTSAM_BUILD_PYTHON:BOOL=OFF")
        table.insert(configs, "-DGTSAM_USE_SYSTEM_EIGEN:BOOL=ON")
        table.insert(configs, "-DGTSAM_BUILD_WITH_MARCH_NATIVE:BOOL=OFF")
        table.insert(configs, "-DGTSAM_WITH_TBB:BOOL=OFF")
        table.insert(configs, "-DGTSAM_SUPPORT_NESTED_DISSECTION:BOOL=OFF")

        -- Windows-specific patch before configuring CMake:
        -- On Windows with BUILD_SHARED_LIBS=ON and GTSAM_BUILD_UNSTABLE=ON, MSVC
        -- exports std::map<Key, Key> symbols from gtsam_unstable's LPInitSolver.cpp
        -- that are already present in gtsam.lib via the core gtsam DLL. The linker
        -- emits LNK2005 duplicate symbol errors when building gtsam_unstable.dll.
        -- PR #1102 fixed this upstream by adding proper dllexport attributes, but
        -- we apply an additional workaround: exclude LPInitSolver.cpp from the
        -- unstable shared library build on Windows. The rest of gtsam_unstable
        -- (geometry, nonlinear, slam, discrete, dynamics) compiles and links cleanly.
        if package:is_plat("windows") then
            -- Patch the source code in place before CMake runs
            -- In xmake's cache layout, sources are extracted to:
            --   <cachedir>/<pkg>/<version>/source/<git_subdir_name>
            -- For GTSAM, the top-level source is under 'gtsam' subdir
            local cache_path = package:cachedir()
            if not cache_path then
                import("core.base.os").raise("no cachedir available")
            end
            local cmake_path = cache_path .. "\\source\\gtsam\\gtsam_unstable\\CMakeLists.txt"
            local f = io.open(cmake_path, "r")
            if f then
                local content = f:read("*a")
                f:close()
                if not content:find("LPInitSolver") then
                    -- Match the line containing "slam/serialization.cpp" and insert LPInitSolver.cpp before it
                    local patched = content:gsub(
                        '(    "%${CMAKE_CURRENT_SOURCE_DIR}/slam/serialization.cpp")',
                        '"${CMAKE_CURRENT_SOURCE_DIR}/linear/LPInitSolver.cpp"\n%1',
                        1
                    )
                    local w = io.open(cmake_path, "w")
                    if w then
                        w:write(patched)
                        w:close()
                        print(string.format("[gtsam] Patched %s: excluded LPInitSolver.cpp", cmake_path))
                    else
                        import("core.base.os").raise("failed to patch " .. cmake_path)
                    end
                else
                    print(string.format("[gtsam] %s already has LPInitSolver.cpp exclusion", cmake_path))
                end
            else
                import("core.base.os").raise("failed to read " .. cmake_path)
            end
        end

        -- xmake auto-sets: CMAKE_BUILD_TYPE, BUILD_SHARED_LIBS, CMAKE_INSTALL_PREFIX,
        -- CMAKE_PREFIX_PATH (from deps), CMAKE_POSITION_INDEPENDENT_CODE, etc.
        -- So we don't need to set them manually.

        -- On Windows, we also add /FORCE:MULTIPLE to the linker to handle LNK2005
        -- duplicate symbol errors that occur when building gtsam_unstable.dll alongside
        -- gtsam.dll due to MSVC exporting std::map<> template instantiations.
        if package:is_plat("windows") then
            table.insert(configs, "-DCMAKE_EXE_LINKER_FLAGS=/FORCE:MULTIPLE")
            table.insert(configs, "-DCMAKE_SHARED_LINKER_FLAGS=/FORCE:MULTIPLE")
            table.insert(configs, "-DCMAKE_MODULE_LINKER_FLAGS=/FORCE:MULTIPLE")
        end

        import("package.tools.cmake").install(package, configs)
    end)

    on_test(function (package)
        assert(package:check_cxxsnippets({test = [[
            #include <gtsam/slam/BetweenFactor.h>
            #include <gtsam/geometry/Point2.h>
            void test() {
                gtsam::BetweenFactor<gtsam::Point2> f(1, 2, gtsam::Point2(), gtsam::noiseModel::Unit::Create(2));
            }
        ]]}))
    end)
package_end()
