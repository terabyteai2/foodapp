import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/menu_image_view.dart';
import '../../core/widgets/pos_compact_ui.dart';
import '../../models/menu_item.dart';
import '../../services/menu_image_service.dart';

class MenuManagementScreen extends StatefulWidget {
  const MenuManagementScreen({super.key});

  @override
  State<MenuManagementScreen> createState() => _MenuManagementScreenState();
}

class _MenuManagementScreenState extends State<MenuManagementScreen> {
  String _selectedCategory = 'All';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final categories = ['All', ...app.categories];
    if (!categories.contains(_selectedCategory)) {
      _selectedCategory = 'All';
    }

    final query = _searchController.text.trim().toLowerCase();
    final items = app.menuItems
        .where((item) {
          final matchesCategory =
              _selectedCategory == 'All' || item.category == _selectedCategory;
          final matchesSearch =
              query.isEmpty ||
              item.name.toLowerCase().contains(query) ||
              item.category.toLowerCase().contains(query) ||
              item.description.toLowerCase().contains(query);
          return matchesCategory && matchesSearch;
        })
        .toList(growable: false);
    final paused = app.menuItems.where((item) => !item.isAvailable).length;

    return Scaffold(
      backgroundColor: PosColors.background,
      body: SafeArea(
        child: CustomScrollView(
          physics: BouncingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(12, 14, 12, 18),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CompactHeader(
                      title: 'Menu',
                      subtitle: '${app.menuItems.length} items · $paused out',
                      actions: [
                        _NewMenuButton(onTap: () => _openMenuForm(context)),
                      ],
                    ),
                    SizedBox(height: 14),
                    CompactSearchField(
                      controller: _searchController,
                      hintText: 'Search items · আইটেম খুঁজুন',
                      onChanged: (_) => setState(() {}),
                    ),
                    if (app.menuItems.isNotEmpty) ...[
                      SizedBox(height: 10),
                      _CategoryStrip(
                        categories: categories,
                        selectedCategory: _selectedCategory,
                        countOf: (cat) => cat == 'All'
                            ? app.menuItems.length
                            : app.menuItems
                                  .where((i) => i.category == cat)
                                  .length,
                        onSelected: (value) =>
                            setState(() => _selectedCategory = value),
                      ),
                    ],
                    SizedBox(height: 10),
                    if (app.menuItems.isEmpty)
                      EmptyCompactState(
                        title: 'No menu items yet',
                        message: 'Add your first item to publish the menu.',
                        icon: Icons.restaurant_menu_rounded,
                      )
                    else if (items.isEmpty)
                      EmptyCompactState(
                        title: 'No items found',
                        message: 'Try another search or category.',
                        icon: Icons.search_off_rounded,
                      )
                    else
                      _MenuList(
                        items: items,
                        onEdit: (item) => _openMenuForm(context, item: item),
                        onDelete: (item) => _confirmDelete(context, item),
                        onAvailabilityChanged: (item, value) async {
                          await app.toggleMenuAvailability(item.id, value);
                        },
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMenuForm(BuildContext context, {MenuItem? item}) async {
    final app = AppScope.of(context);
    final result = await showModalBottomSheet<_MenuFormResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: PosColors.background,
      builder: (context) => _MenuItemForm(initialItem: item),
    );
    if (result == null) return;
    await app.saveMenuItem(
      id: item?.id,
      name: result.name,
      description: result.description,
      category: result.category,
      price: result.price,
      imageUrl: result.imageUrl,
      isAvailable: result.isAvailable,
      preparationTimeMinutes: result.preparationTimeMinutes,
      tags: result.tags,
      createdAt: item?.createdAt,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(item == null ? 'Menu item added' : 'Menu item updated'),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, MenuItem item) async {
    final app = AppScope.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete menu item?'),
        content: Text(
          '${item.name} will be removed from the admin app and future API responses.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await app.deleteMenuItem(item.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Menu item deleted')));
  }
}

class _NewMenuButton extends StatelessWidget {
  const _NewMenuButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Material(
        color: PosColors.primary,
        borderRadius: BorderRadius.circular(9),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, color: PosColors.primaryDark, size: 14),
                SizedBox(width: 4),
                Text(
                  'New',
                  style: TextStyle(
                    color: PosColors.primaryDark,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip({
    required this.categories,
    required this.selectedCategory,
    required this.countOf,
    required this.onSelected,
  });

  final List<String> categories;
  final String selectedCategory;
  final int Function(String category) countOf;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, _) => SizedBox(width: 7),
        itemBuilder: (context, index) {
          final category = categories[index];
          final selected = category == selectedCategory;
          return Material(
            color: selected ? PosColors.primary : PosColors.surface,
            borderRadius: BorderRadius.circular(PosRadii.pill),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onSelected(category),
              child: Container(
                height: 30,
                padding: EdgeInsets.symmetric(horizontal: 11),
                alignment: Alignment.center,
                child: Text(
                  '${category == 'All' ? 'All' : category} ${countOf(category)}',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: selected ? PosColors.primaryDark : PosColors.muted,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MenuList extends StatelessWidget {
  const _MenuList({
    required this.items,
    required this.onEdit,
    required this.onDelete,
    required this.onAvailabilityChanged,
  });

  final List<MenuItem> items;
  final ValueChanged<MenuItem> onEdit;
  final ValueChanged<MenuItem> onDelete;
  final void Function(MenuItem item, bool value) onAvailabilityChanged;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      itemCount: items.length,
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.62,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return _MenuTile(
          item: item,
          onEdit: () => onEdit(item),
          onDelete: () => onDelete(item),
          onAvailabilityChanged: (value) => onAvailabilityChanged(item, value),
        );
      },
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.item,
    required this.onEdit,
    required this.onDelete,
    required this.onAvailabilityChanged,
  });

  final MenuItem item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onAvailabilityChanged;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(
      symbol: '৳',
      decimalDigits: item.price == item.price.roundToDouble() ? 0 : 2,
    );
    final statusColor = item.isAvailable ? PosColors.success : PosColors.danger;

    return Material(
      color: PosColors.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        onLongPress: onDelete,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: PosColors.lineStrong),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 7,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColorFiltered(
                      colorFilter: ColorFilter.mode(
                        item.isAvailable
                            ? Colors.transparent
                            : Colors.black.withValues(alpha: 0.24),
                        BlendMode.darken,
                      ),
                      child: MenuImageView(imageUrl: item.imageUrl),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.10),
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.30),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      top: 8,
                      child: _MenuStatusPill(
                        label: item.isAvailable ? 'Available' : 'Paused',
                        color: statusColor,
                      ),
                    ),
                    Positioned(
                      right: 7,
                      top: 7,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ImageAction(
                            icon: Icons.edit_outlined,
                            tooltip: 'Edit item',
                            onTap: onEdit,
                          ),
                          SizedBox(width: 5),
                          _ImageAction(
                            icon: Icons.delete_outline,
                            tooltip: 'Delete item',
                            onTap: onDelete,
                            danger: true,
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: PosColors.primary,
                          borderRadius: BorderRadius.circular(PosRadii.pill),
                          border: Border.all(color: PosColors.primaryDark),
                        ),
                        child: Text(
                          currency.format(item.price),
                          style: TextStyle(
                            color: PosColors.primaryDark,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 5,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(10, 9, 9, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: PosColors.slate,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                          height: 1.08,
                          letterSpacing: 0,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        item.description.trim().isEmpty
                            ? item.category
                            : item.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: PosColors.muted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      Spacer(),
                      Row(
                        children: [
                          Expanded(child: _CategoryPill(label: item.category)),
                          SizedBox(width: 6),
                          Transform.scale(
                            scale: 0.76,
                            child: Switch.adaptive(
                              value: item.isAvailable,
                              onChanged: onAvailabilityChanged,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuStatusPill extends StatelessWidget {
  const _MenuStatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(PosRadii.pill),
        border: Border.all(color: Colors.black.withValues(alpha: 0.26)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

class _ImageAction extends StatelessWidget {
  const _ImageAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: 30,
        child: Material(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(9),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Icon(
              icon,
              size: 15,
              color: danger ? PosColors.danger : PosColors.primaryDark,
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: 25),
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: PosColors.surfaceWarm,
        borderRadius: BorderRadius.circular(PosRadii.pill),
        border: Border.all(color: PosColors.lineStrong),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: PosColors.muted,
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

class _MenuItemForm extends StatefulWidget {
  const _MenuItemForm({this.initialItem});

  final MenuItem? initialItem;

  @override
  State<_MenuItemForm> createState() => _MenuItemFormState();
}

class _MenuItemFormState extends State<_MenuItemForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _categoryController;
  late final TextEditingController _priceController;
  late final TextEditingController _imageController;
  late final TextEditingController _prepController;
  final MenuImageService _imageService = MenuImageService();
  late bool _isAvailable;
  late Set<String> _tags;
  bool _imageBusy = false;

  @override
  void initState() {
    super.initState();
    final item = widget.initialItem;
    _nameController = TextEditingController(text: item?.name ?? '');
    _descriptionController = TextEditingController(
      text: item?.description ?? '',
    );
    _categoryController = TextEditingController(text: item?.category ?? '');
    _priceController = TextEditingController(
      text: item == null ? '' : item.price.toStringAsFixed(2),
    );
    _imageController = TextEditingController(text: item?.imageUrl ?? '');
    _prepController = TextEditingController(
      text: item?.preparationTimeMinutes?.toString() ?? '',
    );
    _isAvailable = item?.isAvailable ?? true;
    _tags = {...?item?.tags};
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _categoryController.dispose();
    _priceController.dispose();
    _imageController.dispose();
    _prepController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final theme = Theme.of(context);
    final inputTheme = theme.inputDecorationTheme.copyWith(
      fillColor: PosColors.background,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PosRadii.md),
        borderSide: BorderSide(color: PosColors.lineStrong),
      ),
    );
    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: inputTheme,
        chipTheme: theme.chipTheme.copyWith(
          backgroundColor: PosColors.background,
          selectedColor: PosColors.primarySoft,
        ),
      ),
      child: Material(
        color: PosColors.background,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 18),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.initialItem == null
                                ? 'Add Menu Item'
                                : 'Edit Menu Item',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(Icons.close),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    TextFormField(
                      controller: _nameController,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(labelText: 'Item name'),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Item name is required';
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: 10),
                    TextFormField(
                      controller: _descriptionController,
                      maxLines: 3,
                      decoration: InputDecoration(labelText: 'Description'),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Description is required';
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: 10),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 560;
                        final category = TextFormField(
                          controller: _categoryController,
                          decoration: InputDecoration(labelText: 'Category'),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Category is required';
                            }
                            return null;
                          },
                        );
                        final price = TextFormField(
                          controller: _priceController,
                          decoration: InputDecoration(labelText: 'Price'),
                          keyboardType: TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d{0,2}'),
                            ),
                          ],
                          validator: (value) {
                            final price = double.tryParse(value ?? '');
                            if (price == null || price <= 0) {
                              return 'Enter a valid price';
                            }
                            return null;
                          },
                        );
                        if (compact) {
                          return Column(
                            children: [category, SizedBox(height: 10), price],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: category),
                            SizedBox(width: 12),
                            Expanded(child: price),
                          ],
                        );
                      },
                    ),
                    SizedBox(height: 10),
                    _ImagePickerField(
                      controller: _imageController,
                      busy: _imageBusy,
                      onPick: _pickImage,
                      onClear: () {
                        _imageController.clear();
                        setState(() {});
                      },
                      onChanged: (_) => setState(() {}),
                    ),
                    if (_imageController.text.trim().isNotEmpty) ...[
                      SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: AspectRatio(
                          aspectRatio: 1.8,
                          child: MenuImageView(
                            imageUrl: _imageController.text.trim(),
                          ),
                        ),
                      ),
                    ],
                    SizedBox(height: 10),
                    TextFormField(
                      controller: _prepController,
                      decoration: InputDecoration(
                        labelText: 'Preparation time',
                        hintText: 'Minutes, optional',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                    SizedBox(height: 10),
                    SwitchListTile.adaptive(
                      value: _isAvailable,
                      onChanged: (value) =>
                          setState(() => _isAvailable = value),
                      contentPadding: EdgeInsets.zero,
                      title: Text('Available for ordering'),
                    ),
                    SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilterChip(
                          label: Text('Veg'),
                          selected: _tags.contains('veg'),
                          onSelected: (selected) => _toggleTag('veg', selected),
                        ),
                        FilterChip(
                          label: Text('Spicy'),
                          selected: _tags.contains('spicy'),
                          onSelected: (selected) =>
                              _toggleTag('spicy', selected),
                        ),
                        FilterChip(
                          label: Text('Popular'),
                          selected: _tags.contains('popular'),
                          onSelected: (selected) =>
                              _toggleTag('popular', selected),
                        ),
                      ],
                    ),
                    SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _submit,
                        icon: Icon(Icons.save_outlined),
                        label: Text(
                          widget.initialItem == null
                              ? 'Create Item'
                              : 'Save Item',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _toggleTag(String tag, bool selected) {
    setState(() {
      if (selected) {
        _tags.add(tag);
      } else {
        _tags.remove(tag);
      }
    });
  }

  Future<void> _pickImage() async {
    final app = AppScope.of(context);
    setState(() => _imageBusy = true);
    try {
      final dataUrl = await _imageService.pickMenuImageDataUrl();
      if (dataUrl == null) return;
      var imageUrl = dataUrl;
      var uploadWarning = false;
      try {
        imageUrl = await app.uploadMenuImageDataUrl(dataUrl);
      } catch (_) {
        uploadWarning = true;
      }
      _imageController.text = imageUrl;
      if (mounted) setState(() {});
      if (!mounted) return;
      final uploaded = !imageUrl.startsWith('data:image/');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            uploadWarning
                ? 'Image kept locally. Cloud upload will need internet.'
                : uploaded
                ? 'Image uploaded to cloud'
                : 'Image saved locally. It will sync when cloud is ready.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _imageBusy = false);
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _MenuFormResult(
        name: _nameController.text,
        description: _descriptionController.text,
        category: _categoryController.text,
        price: double.parse(_priceController.text),
        imageUrl: _imageController.text,
        isAvailable: _isAvailable,
        preparationTimeMinutes: int.tryParse(_prepController.text),
        tags: _tags.toList(growable: false)..sort(),
      ),
    );
  }
}

class _ImagePickerField extends StatelessWidget {
  const _ImagePickerField({
    required this.controller,
    required this.busy,
    required this.onPick,
    required this.onClear,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onPick;
  final VoidCallback onClear;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: controller,
          onChanged: onChanged,
          decoration: InputDecoration(
            labelText: 'Image URL or gallery image',
            hintText: 'Optional',
            prefixIcon: Icon(Icons.image_outlined),
          ),
          minLines: 1,
          maxLines: 2,
        ),
        SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: busy ? null : onPick,
              icon: busy
                  ? SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.photo_library_outlined),
              label: Text('Choose from gallery'),
            ),
            OutlinedButton.icon(
              onPressed: controller.text.trim().isEmpty ? null : onClear,
              icon: Icon(Icons.clear),
              label: Text('Clear image'),
            ),
          ],
        ),
      ],
    );
  }
}

class _MenuFormResult {
  _MenuFormResult({
    required this.name,
    required this.description,
    required this.category,
    required this.price,
    required this.isAvailable,
    required this.tags,
    this.imageUrl,
    this.preparationTimeMinutes,
  });

  final String name;
  final String description;
  final String category;
  final double price;
  final String? imageUrl;
  final bool isAvailable;
  final int? preparationTimeMinutes;
  final List<String> tags;
}
