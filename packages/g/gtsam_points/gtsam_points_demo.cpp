#include <iostream>
#include <gtsam_points/types/point_cloud.hpp>

int main() {
  gtsam_points::PointCloud cloud;

  // PointCloud::points is Eigen::Vector4d* (homogeneous coordinates)
  std::vector<Eigen::Vector4d> points = {
    Eigen::Vector4d(1.0, 2.0, 3.0, 1.0),
    Eigen::Vector4d(4.0, 5.0, 6.0, 1.0),
    Eigen::Vector4d(7.0, 8.0, 9.0, 1.0)
  };
  cloud.num_points = points.size();
  cloud.points = points.data();

  for (size_t i = 0; i < cloud.num_points; i++) {
    std::cout << "Point " << i << ": "
              << cloud.points[i].x() << " "
              << cloud.points[i].y() << " "
              << cloud.points[i].z() << std::endl;
  }

  std::cout << "gtsam_points demo passed!" << std::endl;
  return 0;
}