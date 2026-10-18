/// 稳定排序。Dart 的 `List.sort` 不保证稳定，而引擎的若干输出顺序依赖 Python `sorted` 的稳定性
/// （同一时刻的事件保持输入顺序、同日同账户的缺口点保持时间线顺序）。
library;

/// 返回按 [compare] 稳定排序的新列表（相等元素保持原顺序；归并排序）。
List<T> stableSorted<T>(Iterable<T> items, int Function(T a, T b) compare) {
  final list = List<T>.of(items);
  if (list.length < 2) {
    return list;
  }
  var source = list;
  var target = List<T>.of(list);
  for (var width = 1; width < source.length; width *= 2) {
    for (var lo = 0; lo < source.length; lo += 2 * width) {
      final mid = lo + width < source.length ? lo + width : source.length;
      final hi = lo + 2 * width < source.length
          ? lo + 2 * width
          : source.length;
      var i = lo;
      var j = mid;
      var k = lo;
      while (i < mid && j < hi) {
        // `<= 0`：相等时取左半部分的元素，保持稳定。
        if (compare(source[i], source[j]) <= 0) {
          target[k++] = source[i++];
        } else {
          target[k++] = source[j++];
        }
      }
      while (i < mid) {
        target[k++] = source[i++];
      }
      while (j < hi) {
        target[k++] = source[j++];
      }
    }
    final swap = source;
    source = target;
    target = swap;
  }
  return source;
}
