package("small_gicp")
    set_homepage("https://github.com/koide3/small_gicp")
    set_description("Efficient and parallel algorithms for point cloud registration [C++, Python]")
    set_license("MIT")

    add_urls("https://github.com/koide3/small_gicp.git")

    -- Available tags and their commit SHAs
    add_versions("v0.1.0", "ac6c79acb6fba9b4dd2c26392eebd8704eafab2e")
    add_versions("v0.1.3", "ad7271525934970ce94a65d473a13926eabc7056")
    add_versions("v1.0.0", "fd29d8cf94cf05ed7ad21c81c27b65963110adb5")

    add_deps("cmake", "gtsam 4.2.2", "eigen")
    add_deps("boost", {configs = {filesystem = true, program_options = true}})

    on_load(function (package)
        -- TBB is optional; skip on Windows due to build complexity
        if not package:is_plat("windows") then
            package:add("deps", "tbb")
        end
    end)

    on_install("windows", "linux", "macosx", function (package)
        -- xmake provides path.join() as global in on_install
        import("package.tools.cmake")

        local configs = {}

        -- small_gicp CMake options
        table.insert(configs, "-DBUILD_EXAMPLES=OFF")
        table.insert(configs, "-DBUILD_TESTS=OFF")
        table.insert(configs, "-DBUILD_PYTHON_BINDINGS=OFF")
        table.insert(configs, "-DBUILD_WITH_OPENMP=OFF")
        table.insert(configs, "-DBUILD_WITH_TBB=OFF")

        -- Fix C++ standard requirement for MSVC
        if package:is_plat("windows") then
            -- Override the MSVC runtime to match gtsam (dynamic /MD is already default)
            table.insert(configs, "-DCMAKE_WINDOWS_EXPORT_ALL_SYMBOLS=ON")
        end

        -- Patch the reduction_omp.hpp to fix MSVC compatibility issues
        if package:is_plat("windows") then
            local cachedir = assert(package:cachedir(), "no cachedir available")
            local sourcedir = path.join(cachedir, "source", "small_gicp")
            local reduction_omp = path.join(sourcedir, "include", "small_gicp", "registration", "reduction_omp.hpp")
            
            -- Replace the entire file content with a minimal working version
            local fallback_content = [[
#pragma once

#include <Eigen/Dense>
#include <vector>
#include <tuple>

namespace small_gicp {

/// @brief Dummy parallel reduction backend for MSVC compatibility
struct ParallelReductionOMP {
    ParallelReductionOMP() : num_threads(1) {}  // Single-threaded on Windows

    template <typename TargetPointCloud, typename SourcePointCloud, 
              typename TargetTree, typename CorrespondenceRejector, typename Factor>
    std::tuple<Eigen::Matrix<double, 6, 6>, Eigen::Matrix<double, 6, 1>, double> linearize(
        const TargetPointCloud& target,
        const SourcePointCloud& source,
        const TargetTree& target_tree,
        const CorrespondenceRejector& rejector,
        const Eigen::Isometry3d& T,
        std::vector<Factor>& factors) const {
        // Accumulate linearization results sequentially
        Eigen::Matrix<double, 6, 6> H = Eigen::Matrix<double, 6, 6>::Zero();
        Eigen::Matrix<double, 6, 1> b = Eigen::Matrix<double, 6, 1>::Zero();
        double e = 0.0;

        for (size_t i = 0; i < factors.size(); i++) {
            Eigen::Matrix<double, 6, 6> Hi;
            Eigen::Matrix<double, 6, 1> bi;
            double ei;
            if (!factors[i].linearize(target, source, target_tree, T, i, rejector, &Hi, &bi, &ei)) {
                continue;
            }
            H += Hi;
            b += bi;
            e += ei;
        }

        return {H, b, e};
    }

    template <typename TargetPointCloud, typename SourcePointCloud, typename Factor>
    double error(const TargetPointCloud& target, const SourcePointCloud& source, 
                 const Eigen::Isometry3d& T, std::vector<Factor>& factors) const {
        double sum_e = 0.0;
        for (size_t i = 0; i < factors.size(); i++) {
            sum_e += factors[i].error(target, source, T);
        }
        return sum_e;
    }

    int num_threads;
};

}  // namespace small_gicp
]]
            local f = io.open(reduction_omp, "w")
            if f then
                f:write(fallback_content)
                f:close()
                print(string.format("[small_gicp] Replaced %s with MSVC-compatible version", reduction_omp))
            else
                os.raise("failed to write " .. reduction_omp)
            end
        end

        import("package.tools.cmake").install(package, configs)
    end)

    on_test(function (package)
        assert(package:check_cxxsnippets({test = [[
            #define _USE_MATH_DEFINES
            #include <small_gicp/registration/reduction_omp.hpp>
            void test() {
                small_gicp::ParallelReductionOMP reduction;
            }
        ]]}))
    end)
package_end()
