import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';
import 'package:printing/printing.dart';

import '../../models/app_user.dart';
import '../../models/attendance_session.dart';
import '../../repositories/attendance_repository.dart';
import '../../services/attendance_tracking_service.dart';
import '../../services/auth_service.dart';
import '../../services/location_address_service.dart';
import '../../theme/app_colors.dart';
import 'widgets/leave_management_panel.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  AttendanceSession? _session;
  List<AttendanceSession> _personalHistory = [];
  List<AttendanceDailyEmployee> _dailyEmployees = [];
  List<AttendanceSession> _ownerHistory = [];
  AppUser? _profile;
  bool _loading = true;
  bool _working = false;
  bool _showTeam = true;
  Timer? _clock;
  DateTime _now = DateTime.now();
  DateTime _selectedDate = DateTime.now();
  late DateTime _reportFrom;
  late DateTime _reportTo;

  bool get _isOwner => _profile?.isOwner == true;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _reportTo = DateTime(today.year, today.month, today.day);
    _reportFrom = _reportTo.subtract(const Duration(days: 29));
    _load();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _load({bool showLoader = false}) async {
    if (showLoader && mounted) setState(() => _loading = true);
    try {
      final profile = await AuthService.instance.loadCurrentProfile();
      final personalResults = await Future.wait([
        AttendanceRepository.instance.getOpenSession(),
        AttendanceRepository.instance.history(),
      ]);

      List<AttendanceDailyEmployee> dailyEmployees = [];
      List<AttendanceSession> ownerHistory = [];
      if (profile?.isOwner == true) {
        final ownerResults = await Future.wait([
          AttendanceRepository.instance.ownerDailyOverview(_selectedDate),
          AttendanceRepository.instance.ownerHistory(
            from: _reportFrom,
            to: _reportTo,
          ),
        ]);
        dailyEmployees = ownerResults[0] as List<AttendanceDailyEmployee>;
        ownerHistory = ownerResults[1] as List<AttendanceSession>;
      }

      if (!mounted) return;
      setState(() {
        _profile = profile;
        _session = personalResults[0] as AttendanceSession?;
        _personalHistory = personalResults[1] as List<AttendanceSession>;
        _dailyEmployees = dailyEmployees;
        _ownerHistory = ownerHistory;
        _loading = false;
        if (!_isOwner) _showTeam = false;
      });

      if (_session != null) {
        await AttendanceTrackingService.instance.start(
          sessionId: _session!.id,
          employeeId: _session!.employeeId,
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('Attendance could not be loaded. Pull down to try again.');
    }
  }

  Future<Position> _position() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Turn on Location Services before continuing.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('Location permission is required for attendance.');
    }

    // Browsers support only their own foreground geolocation permission.
    // Requesting the mobile "always" permission on web causes check-in to
    // fail before Geolocator can obtain the browser position.
    if (!kIsWeb) {
      await Permission.locationAlways.request();
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        timeLimit: Duration(seconds: 30),
      ),
    );
    final maximumAccuracy = kIsWeb ? 250.0 : 100.0;
    if (position.accuracy > maximumAccuracy) {
      throw StateError(
        'Location accuracy is too low. Enable precise location, move near a window, and try again.',
      );
    }
    return position;
  }

  Future<void> _checkIn() async {
    setState(() => _working = true);
    try {
      final position = await _position();
      final address = await LocationAddressService.instance.resolve(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      final session = await AttendanceRepository.instance.checkIn(
        position,
        address: address,
      );
      await AttendanceTrackingService.instance.start(
        sessionId: session.id,
        employeeId: session.employeeId,
      );
      if (!mounted) return;
      _message('Checked in. GPS tracking is active.');
      await _load();
    } catch (error) {
      if (mounted) {
        _message(
          error is StateError
              ? error.message.toString()
              : 'Check-in failed. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _checkOut() async {
    final currentSession = _session;
    if (currentSession == null) return;
    setState(() => _working = true);
    try {
      final position = await _position();
      final address = await LocationAddressService.instance.resolve(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      await AttendanceRepository.instance.checkOut(
        currentSession,
        position,
        address: address,
      );
      AttendanceTrackingService.instance.stop();
      if (!mounted) return;
      _message('Checked out. GPS tracking has stopped.');
      await _load();
    } catch (error) {
      if (mounted) {
        _message(
          error is StateError
              ? error.message.toString()
              : 'Check-out failed. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _selectDailyDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (selected == null || !mounted) return;
    setState(() => _selectedDate = selected);
    await _load(showLoader: true);
  }

  Future<void> _selectReportDate({required bool from}) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: from ? _reportFrom : _reportTo,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (selected == null || !mounted) return;

    var nextFrom = from ? selected : _reportFrom;
    var nextTo = from ? _reportTo : selected;
    if (nextFrom.isAfter(nextTo)) {
      if (from) {
        nextTo = selected;
      } else {
        nextFrom = selected;
      }
    }
    setState(() {
      _reportFrom = nextFrom;
      _reportTo = nextTo;
    });
    await _load(showLoader: true);
  }

  Future<void> _exportReport() async {
    if (_ownerHistory.isEmpty) {
      _message('There are no attendance records in this date range.');
      return;
    }

    setState(() => _working = true);
    try {
      final document = pw.Document();
      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(28),
          build: (_) => [
            pw.Text(
              'EWAY LINK Attendance Report',
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              '${_date(_reportFrom)} to ${_date(_reportTo)}',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 18),
            pw.TableHelper.fromTextArray(
              headers: const [
                'Employee',
                'Date',
                'Check In',
                'Check-in Place',
                'Check Out',
                'Checkout Place',
                'Hours',
                'GPS Points',
                'Accuracy',
                'Status',
              ],
              data: _ownerHistory
                  .map(
                    (session) => [
                      _displayName(session),
                      _date(session.workDate),
                      _time(session.checkedInAt),
                      session.checkInAddress,
                      session.checkedOutAt == null
                          ? 'Tracking'
                          : _time(session.checkedOutAt!),
                      session.checkedOutAt == null
                          ? 'Tracking active'
                          : session.checkOutAddress,
                      _duration(session.workedDuration),
                      session.locationPointCount.toString(),
                      '${session.checkInAccuracy.toStringAsFixed(0)} m',
                      session.isOpen ? 'Checked In' : 'Completed',
                    ],
                  )
                  .toList(),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.blue700,
              ),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellPadding: const pw.EdgeInsets.all(5),
              border: pw.TableBorder.all(
                color: PdfColors.grey300,
                width: 0.5,
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Text(
              'Generated ${_dateTime(DateTime.now())}',
              style: const pw.TextStyle(
                fontSize: 8,
                color: PdfColors.grey700,
              ),
            ),
          ],
        ),
      );

      await Printing.sharePdf(
        bytes: await document.save(),
        filename:
            'EWAY_Attendance_${_fileDate(_reportFrom)}_${_fileDate(_reportTo)}.pdf',
      );
    } catch (_) {
      if (mounted) _message('The attendance report could not be exported.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = constraints.maxWidth < 700 ? 16.0 : 24.0;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              20,
              horizontalPadding,
              36,
            ),
            children: [
              _pageHeader(),
              if (_isOwner) ...[
                const SizedBox(height: 18),
                _sectionSelector(),
              ],
              const SizedBox(height: 20),
              if (_isOwner && _showTeam)
                _ownerContent(constraints.maxWidth)
              else
                _personalContent(constraints.maxWidth),
              if (_profile != null) ...[
                const SizedBox(height: 24),
                LeaveManagementPanel(profile: _profile!),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _pageHeader() {
    final name = _profile?.fullName.trim().isNotEmpty == true
        ? _profile!.fullName.trim()
        : 'Employee';
    if (MediaQuery.sizeOf(context).width < 700) {
      return Row(
        children: [
          Expanded(
            child: Text(
              '$name  •  ${_date(_now)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Refresh attendance',
            onPressed: _working ? null : () => _load(showLoader: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      );
    }
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isOwner ? 'Attendance Management' : 'My Attendance',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: Color(0xFF172033),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$name  •  ${_date(_now)}',
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        IconButton.filledTonal(
          tooltip: 'Refresh attendance',
          onPressed: _working ? null : () => _load(showLoader: true),
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }

  Widget _sectionSelector() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF4F8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sectionButton(
              label: 'Team Overview',
              icon: Icons.groups_2_outlined,
              selected: _showTeam,
              onTap: () => setState(() => _showTeam = true),
            ),
            _sectionButton(
              label: 'My Attendance',
              icon: Icons.person_outline,
              selected: !_showTeam,
              onTap: () => setState(() => _showTeam = false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? AppColors.primary : const Color(0xFF64748B),
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: selected
                    ? const Color(0xFF172033)
                    : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _personalContent(double width) {
    final active = _session?.isOpen == true;
    AttendanceSession? todaySession;
    for (final item in _personalHistory) {
      if (item.workDate.year == _now.year &&
          item.workDate.month == _now.month &&
          item.workDate.day == _now.day) {
        todaySession = item;
        break;
      }
    }
    todaySession ??= _session;
    final completedToday = !active && todaySession != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(width < 700 ? 20 : 28),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: active
                  ? const [Color(0xFFECFDF5), Color(0xFFF7FFFB)]
                  : const [Colors.white, Color(0xFFF8FBFD)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active
                  ? const Color(0xFF78D7B0)
                  : const Color(0xFFDDE6EC),
            ),
          ),
          child: Wrap(
            spacing: 28,
            runSpacing: 24,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize:
                    width < 700 ? MainAxisSize.max : MainAxisSize.min,
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      color: active
                          ? const Color(0xFFD9F7E9)
                          : const Color(0xFFE9F4FA),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      active
                          ? Icons.location_on
                          : completedToday
                          ? Icons.task_alt_rounded
                          : Icons.location_off_outlined,
                      size: 32,
                      color: active
                          ? const Color(0xFF16845B)
                          : completedToday
                          ? const Color(0xFF6B5DD3)
                          : AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      Text(
                        active
                            ? 'GPS TRACKING ACTIVE'
                            : completedToday
                            ? 'ATTENDANCE COMPLETED TODAY'
                            : 'NOT CHECKED IN',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: active
                              ? const Color(0xFF16845B)
                              : const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _time(_now),
                        style: const TextStyle(
                          fontSize: 38,
                          height: 1,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF172033),
                        ),
                      ),
                      if (active) ...[
                        const SizedBox(height: 7),
                        Text(
                          'Checked in at ${_time(_session!.checkedInAt)}',
                          style: const TextStyle(color: Color(0xFF475569)),
                        ),
                        const SizedBox(height: 3),
                        SizedBox(
                          width: width < 700
                              ? (width - 130).clamp(150.0, 360.0).toDouble()
                              : 360,
                          child: Text(
                            _session!.checkInAddress,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF475569),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      if (completedToday) ...[
                        const SizedBox(height: 7),
                        Text(
                          'Checked in ${_time(todaySession.checkedInAt)}  •  '
                          'Checked out ${_time(todaySession.checkedOutAt!)}',
                          style: const TextStyle(
                            color: Color(0xFF475569),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'Operational access remains unlocked for today.',
                          style: TextStyle(color: Color(0xFF64748B)),
                        ),
                      ],
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(
                width: 220,
                height: 52,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: active
                        ? const Color(0xFFCF3E4F)
                        : const Color(0xFF16845B),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _working || completedToday
                      ? null
                      : active
                      ? _checkOut
                      : _checkIn,
                  icon: _working
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(active ? Icons.logout : Icons.login),
                  label: Text(
                    active
                        ? 'CHECK OUT'
                        : completedToday
                        ? 'DAY COMPLETED'
                        : 'CHECK IN',
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Recent Attendance',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        if (_personalHistory.isEmpty)
          _emptyPanel('No attendance records yet.')
        else
          ..._personalHistory.map(_personalHistoryCard),
      ],
    );
  }

  Widget _personalHistoryCard(AttendanceSession item) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: item.isOpen
              ? const Color(0xFFFFF3D8)
              : const Color(0xFFE4F8EE),
          child: Icon(
            item.isOpen ? Icons.location_on : Icons.task_alt,
            color: item.isOpen
                ? const Color(0xFFC47C08)
                : const Color(0xFF16845B),
          ),
        ),
        title: Text(
          _date(item.workDate),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          'In ${_time(item.checkedInAt)}  •  '
          'Out ${item.checkedOutAt == null ? '—' : _time(item.checkedOutAt!)}\n'
          '${item.checkInAddress}'
          '${item.checkedOutAt == null ? '' : ' → ${item.checkOutAddress}'}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        trailing: Text(
          item.isOpen ? 'Tracking' : _duration(item.workedDuration),
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: item.isOpen
                ? const Color(0xFFC47C08)
                : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }

  Widget _ownerContent(double width) {
    final present = _dailyEmployees.where((item) => item.isPresent).length;
    final tracking = _dailyEmployees.where((item) => item.isTracking).length;
    final completed = _dailyEmployees.where((item) => item.isCompleted).length;
    final onLeave = _dailyEmployees.where((item) => item.isOnLeave).length;
    final isWeekend = _dailyEmployees.any((item) => item.isWeekend);
    final absent = isWeekend ? 0 : _dailyEmployees.length - present - onLeave;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final cards = [
              _metricCard(
                width: constraints.maxWidth < 700 ? 142 : 0,
                label: 'Present',
                value: present,
                icon: Icons.how_to_reg,
                color: const Color(0xFF16845B),
              ),
              _metricCard(
                width: constraints.maxWidth < 700 ? 142 : 0,
                label: 'Tracking Now',
                value: tracking,
                icon: Icons.location_on,
                color: AppColors.primary,
              ),
              _metricCard(
                width: constraints.maxWidth < 700 ? 142 : 0,
                label: 'Checked Out',
                value: completed,
                icon: Icons.task_alt,
                color: const Color(0xFF6B5DD3),
              ),
              _metricCard(
                width: constraints.maxWidth < 700 ? 142 : 0,
                label: 'On Leave',
                value: onLeave,
                icon: Icons.event_available_outlined,
                color: const Color(0xFF9A5B18),
              ),
              _metricCard(
                width: constraints.maxWidth < 700 ? 142 : 0,
                label: 'Absent',
                value: absent,
                icon: Icons.person_off_outlined,
                color: const Color(0xFFCF3E4F),
              ),
            ];
            if (constraints.maxWidth < 700) {
              return SizedBox(
                height: 80,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: cards.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 9),
                  itemBuilder: (context, index) => cards[index],
                ),
              );
            }
            final columns = constraints.maxWidth >= 900
                ? 5
                : constraints.maxWidth >= 320
                    ? 2
                    : 1;
            final cardWidth =
                (constraints.maxWidth - ((columns - 1) * 12)) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _metricCard(
              width: cardWidth,
              label: 'Present',
              value: present,
              icon: Icons.how_to_reg,
              color: const Color(0xFF16845B),
            ),
                _metricCard(
              width: cardWidth,
              label: 'Tracking Now',
              value: tracking,
              icon: Icons.location_on,
              color: AppColors.primary,
            ),
                _metricCard(
              width: cardWidth,
              label: 'Checked Out',
              value: completed,
              icon: Icons.task_alt,
              color: const Color(0xFF6B5DD3),
            ),
                _metricCard(
              width: cardWidth,
              label: 'On Leave',
              value: onLeave,
              icon: Icons.event_available_outlined,
              color: const Color(0xFF9A5B18),
            ),
                _metricCard(
              width: cardWidth,
              label: 'Absent',
              value: absent,
              icon: Icons.person_off_outlined,
              color: const Color(0xFFCF3E4F),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 22),
        _panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _panelTitle(
                title: 'Daily Attendance Status',
                subtitle: _date(_selectedDate),
                action: OutlinedButton.icon(
                  onPressed: _working ? null : _selectDailyDate,
                  icon: const Icon(Icons.calendar_month_outlined, size: 18),
                  label: const Text('Change Date'),
                ),
              ),
              const SizedBox(height: 16),
              if (_dailyEmployees.isEmpty)
                _emptyPanel('No active employees were found.')
              else if (width >= 850)
                _dailyTable()
              else
                ..._dailyEmployees.map(_dailyEmployeeCard),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _panelTitle(
                title: 'Attendance History & Reports',
                subtitle:
                    '${_date(_reportFrom)}  —  ${_date(_reportTo)}',
                action: FilledButton.icon(
                  onPressed: _working ? null : _exportReport,
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('Export PDF'),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: _working
                        ? null
                        : () => _selectReportDate(from: true),
                    icon: const Icon(Icons.event, size: 17),
                    label: Text('From ${_date(_reportFrom)}'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _working
                        ? null
                        : () => _selectReportDate(from: false),
                    icon: const Icon(Icons.event_available, size: 17),
                    label: Text('To ${_date(_reportTo)}'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_ownerHistory.isEmpty)
                _emptyPanel('No attendance records in this date range.')
              else if (width >= 900)
                _historyTable()
              else
                ..._ownerHistory.map(_ownerHistoryCard),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metricCard({
    required double width,
    required String label,
    required int value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Text(
                value.toString(),
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                ),
              ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dailyTable() {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: DataTable(
        headingRowColor: WidgetStateProperty.all(const Color(0xFFF4F7FA)),
        columns: const [
          DataColumn(label: Text('EMPLOYEE')),
          DataColumn(label: Text('STATUS')),
          DataColumn(label: Text('CHECK IN')),
          DataColumn(label: Text('CHECK-IN PLACE')),
          DataColumn(label: Text('CHECK OUT')),
          DataColumn(label: Text('CHECKOUT PLACE')),
          DataColumn(label: Text('DURATION')),
          DataColumn(label: Text('GPS POINTS')),
          DataColumn(label: Text('ACCURACY')),
        ],
        rows: _dailyEmployees.map((employee) {
          final session = employee.session;
          return DataRow(
            cells: [
              DataCell(_employeeIdentity(employee.employeeName, employee.role)),
              DataCell(_dailyStatusChip(employee)),
              DataCell(Text(session == null ? '—' : _time(session.checkedInAt))),
              DataCell(
                SizedBox(
                  width: 210,
                  child: Text(session?.checkInAddress ?? '—'),
                ),
              ),
              DataCell(
                Text(
                  session?.checkedOutAt == null
                      ? '—'
                      : _time(session!.checkedOutAt!),
                ),
              ),
              DataCell(
                SizedBox(
                  width: 210,
                  child: Text(
                    session?.checkedOutAt == null
                        ? '—'
                        : session!.checkOutAddress,
                  ),
                ),
              ),
              DataCell(
                Text(session == null ? '—' : _duration(session.workedDuration)),
              ),
              DataCell(Text(session?.locationPointCount.toString() ?? '—')),
              DataCell(
                Text(
                  session == null
                      ? '—'
                      : '${session.checkInAccuracy.toStringAsFixed(0)} m',
                ),
              ),
            ],
          );
        }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _dailyEmployeeCard(AttendanceDailyEmployee employee) {
    final session = employee.session;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFCFD),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _employeeIdentity(employee.employeeName, employee.role),
              ),
              _dailyStatusChip(employee),
            ],
          ),
          if (session != null) ...[
            const SizedBox(height: 13),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                _fact('Check in', _time(session.checkedInAt)),
                _fact('Check-in place', session.checkInAddress),
                _fact(
                  'Check out',
                  session.checkedOutAt == null
                      ? 'Tracking'
                      : _time(session.checkedOutAt!),
                ),
                if (session.checkedOutAt != null)
                  _fact('Checkout place', session.checkOutAddress),
                _fact('Duration', _duration(session.workedDuration)),
                _fact('GPS points', session.locationPointCount.toString()),
                _fact(
                  'Accuracy',
                  '${session.checkInAccuracy.toStringAsFixed(0)} m',
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _historyTable() {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: DataTable(
        headingRowColor: WidgetStateProperty.all(const Color(0xFFF4F7FA)),
        columns: const [
          DataColumn(label: Text('EMPLOYEE')),
          DataColumn(label: Text('DATE')),
          DataColumn(label: Text('CHECK IN')),
          DataColumn(label: Text('CHECK-IN PLACE')),
          DataColumn(label: Text('CHECK OUT')),
          DataColumn(label: Text('CHECKOUT PLACE')),
          DataColumn(label: Text('HOURS')),
          DataColumn(label: Text('GPS POINTS')),
          DataColumn(label: Text('STATUS')),
        ],
        rows: _ownerHistory.map((session) {
          return DataRow(
            cells: [
              DataCell(
                Text(
                  _displayName(session),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              DataCell(Text(_date(session.workDate))),
              DataCell(Text(_time(session.checkedInAt))),
              DataCell(
                SizedBox(
                  width: 210,
                  child: Text(session.checkInAddress),
                ),
              ),
              DataCell(
                Text(
                  session.checkedOutAt == null
                      ? '—'
                      : _time(session.checkedOutAt!),
                ),
              ),
              DataCell(
                SizedBox(
                  width: 210,
                  child: Text(
                    session.checkedOutAt == null
                        ? '—'
                        : session.checkOutAddress,
                  ),
                ),
              ),
              DataCell(Text(_duration(session.workedDuration))),
              DataCell(Text(session.locationPointCount.toString())),
              DataCell(_sessionStatusChip(session)),
            ],
          );
        }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _ownerHistoryCard(AttendanceSession session) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFCFD),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _displayName(session),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _sessionStatusChip(session),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _date(session.workDate),
            style: const TextStyle(color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              _fact('Check in', _time(session.checkedInAt)),
              _fact('Check-in place', session.checkInAddress),
              _fact(
                'Check out',
                session.checkedOutAt == null
                    ? 'Tracking'
                    : _time(session.checkedOutAt!),
              ),
              if (session.checkedOutAt != null)
                _fact('Checkout place', session.checkOutAddress),
              _fact('Duration', _duration(session.workedDuration)),
              _fact('GPS points', session.locationPointCount.toString()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _employeeIdentity(String name, String role) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 17,
          backgroundColor: const Color(0xFFE6F3FA),
          child: Text(
            _initials(name),
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 9),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(
              _titleCase(role),
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _dailyStatusChip(AttendanceDailyEmployee employee) {
    if (employee.isOnLeave && !employee.isPresent) {
      return _statusChip('On Leave', const Color(0xFF9A5B18));
    }
    if (employee.isTracking) {
      return _statusChip('Tracking', const Color(0xFF0F8CCF));
    }
    if (employee.isCompleted) {
      return _statusChip('Completed', const Color(0xFF16845B));
    }
    if (employee.isWeekend) {
      return _statusChip('Weekend Off', const Color(0xFF64748B));
    }
    return _statusChip('Absent', const Color(0xFFCF3E4F));
  }

  Widget _sessionStatusChip(AttendanceSession session) {
    return _statusChip(
      session.isOpen ? 'Tracking' : 'Completed',
      session.isOpen ? const Color(0xFF0F8CCF) : const Color(0xFF16845B),
    );
  }

  Widget _statusChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _fact(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _panel({required Widget child}) {
    final mobile = MediaQuery.sizeOf(context).width < 600;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(mobile ? 14 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: child,
    );
  }

  Widget _panelTitle({
    required String title,
    required String subtitle,
    required Widget action,
  }) {
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        action,
      ],
    );
  }

  Widget _emptyPanel(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFF64748B)),
      ),
    );
  }

  String _displayName(AttendanceSession session) {
    if (session.employeeName.trim().isNotEmpty) return session.employeeName;
    if (session.employeeId == _profile?.id &&
        _profile?.fullName.trim().isNotEmpty == true) {
      return _profile!.fullName.trim();
    }
    return 'Employee';
  }

  String _initials(String value) {
    final words = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return 'E';
    if (words.length == 1) return words.first.substring(0, 1).toUpperCase();
    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }

  String _titleCase(String value) {
    if (value.isEmpty) return value;
    return '${value[0].toUpperCase()}${value.substring(1).toLowerCase()}';
  }

  String _time(DateTime value) {
    return _formatPakistanTime(_pakistanTime(value));
  }

  String _date(DateTime value) {
    return '${value.day.toString().padLeft(2, '0')}/'
        '${value.month.toString().padLeft(2, '0')}/${value.year}';
  }

  String _fileDate(DateTime value) {
    return '${value.year}${value.month.toString().padLeft(2, '0')}'
        '${value.day.toString().padLeft(2, '0')}';
  }

  String _dateTime(DateTime value) {
    final pakistan = _pakistanTime(value);
    return '${_date(pakistan)} ${_formatPakistanTime(pakistan)}';
  }

  DateTime _pakistanTime(DateTime value) {
    return value.toUtc().add(const Duration(hours: 5));
  }

  String _formatPakistanTime(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final period = value.hour < 12 ? 'AM' : 'PM';
    return '${hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')} $period PKT';
  }

  String _duration(Duration duration) {
    if (duration.isNegative) return '0h 00m';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }
}
