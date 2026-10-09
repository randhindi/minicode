#include <vector>
#include "local.hpp"

namespace fhe {
template <typename T>
class Ciphertext final {
public:
    explicit Ciphertext(std::vector<T> data) : data_(std::move(data)) {}
    constexpr bool empty() const noexcept { return data_.empty(); }
private:
    std::vector<T> data_; // payload
};
}  // namespace fhe
