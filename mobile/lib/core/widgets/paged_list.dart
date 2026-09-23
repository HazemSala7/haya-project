import 'package:flutter/material.dart';

import '../models/records.dart';
import '../theme.dart';
import 'ui.dart';

/// A list the server pages, loaded as it is scrolled.
///
/// Pull-to-refresh starts again from page one; reaching the last few rows asks
/// for the next page. Change [filterKey] and the list starts over — that is
/// how a filter chip resets it without the screen tracking pages itself.
class PagedList<T> extends StatefulWidget {
  const PagedList({
    super.key,
    required this.fetch,
    required this.itemBuilder,
    required this.filterKey,
    this.header = const [],
    this.empty,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 96),
    this.separator = 10,
  });

  final Future<PageOf<T>> Function(int page) fetch;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final Object filterKey;

  /// Widgets above the rows — filters, a count, a note. Scroll with the list.
  final List<Widget> header;
  final Widget? empty;
  final EdgeInsetsGeometry padding;
  final double separator;

  @override
  State<PagedList<T>> createState() => PagedListState<T>();
}

class PagedListState<T> extends State<PagedList<T>> {
  final _items = <T>[];
  var _page = 0;
  var _hasMore = true;
  var _loading = false;
  Object? _error;
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  @override
  void didUpdateWidget(covariant PagedList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filterKey != widget.filterKey) reload();
  }

  /// Start again from the first page. Public so a screen can call it after a
  /// write that changes what the list should say.
  Future<void> reload() async {
    _generation++;
    setState(() {
      _items.clear();
      _page = 0;
      _hasMore = true;
      _loading = false;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;

    final generation = _generation;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final page = await widget.fetch(_page + 1);
      // A filter changed while this page was in flight. Its rows belong to a
      // list nobody is looking at any more.
      if (!mounted || generation != _generation) return;

      setState(() {
        _items.addAll(page.items);
        _page = page.currentPage;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[...widget.header];

    if (_items.isEmpty) {
      if (_loading) {
        rows.add(const AppLoading());
      } else if (_error != null) {
        rows.add(AppError(error: _error!, onRetry: _loadMore));
      } else {
        rows.add(widget.empty ?? const AppEmpty(title: 'ما في شي هون'));
      }
    } else {
      for (var i = 0; i < _items.length; i++) {
        rows.add(widget.itemBuilder(context, _items[i]));
        if (i < _items.length - 1) rows.add(SizedBox(height: widget.separator));
      }

      if (_hasMore || _loading) {
        rows.add(
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2)),
            ),
          ),
        );
      } else if (_error != null) {
        rows.add(AppError(error: _error!, onRetry: _loadMore));
      }
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 400) _loadMore();
        return false;
      },
      child: RefreshIndicator(
        onRefresh: reload,
        color: AppColors.brand,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: widget.padding,
          children: rows,
        ),
      ),
    );
  }
}
