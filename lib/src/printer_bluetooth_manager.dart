/*
 * esc_pos_bluetooth
 * Created by Andrey Ushakov
 *
 * Copyright (c) 2019-2020. All rights reserved.
 * See LICENSE for distribution and usage details.
 */

import 'dart:async';
import 'dart:io';
import 'package:rxdart/rxdart.dart';
import 'package:flutter_bluetooth_basic/flutter_bluetooth_basic.dart';
import './enums.dart';

/// Bluetooth printer
class PrinterBluetooth {
  PrinterBluetooth(this._device);
  final BluetoothDevice _device;

  String? get name => _device.name;
  String? get address => _device.address;
  int? get type => _device.type;
}

/// Printer Bluetooth Manager
class PrinterBluetoothManager {
  final BluetoothManager _bluetoothManager = BluetoothManager.instance;
  bool _isPrinting = false;
  bool _isConnected = false;
  StreamSubscription? _scanResultsSubscription;
  StreamSubscription? _isScanningSubscription;
  PrinterBluetooth? _selectedPrinter;

  final BehaviorSubject<bool> _isScanning = BehaviorSubject.seeded(false);
  Stream<bool> get isScanningStream => _isScanning.stream;

  final BehaviorSubject<List<PrinterBluetooth>> _scanResults =
      BehaviorSubject.seeded([]);
  Stream<List<PrinterBluetooth>> get scanResults => _scanResults.stream;

  List<int> _bufferedBytes = [];
  int _queueSleepTimeMs = 20;
  int _chunkSizeBytes = 20;
  int _connectionTimeOut = 10;

  Future _runDelayed(int seconds) {
    return Future<dynamic>.delayed(Duration(seconds: seconds));
  }

  Future<void> startScan(Duration timeout) async {
    _scanResults.add(<PrinterBluetooth>[]);

    _bluetoothManager.startScan(timeout: timeout);

    _scanResultsSubscription = _bluetoothManager.scanResults.listen((devices) {
      _scanResults.add(devices.map((d) => PrinterBluetooth(d)).toList());
    });

    _isScanningSubscription =
        _bluetoothManager.isScanning.listen((isScanningCurrent) async {
      // If isScanning value changed (scan just stopped)
      if (_isScanning.value! && !isScanningCurrent) {
        _scanResultsSubscription!.cancel();
        _isScanningSubscription!.cancel();
      }
      _isScanning.add(isScanningCurrent);
    });
  }

  Future<void> stopScan() async {
    await _bluetoothManager.stopScan();
    await _isScanningSubscription?.cancel();
  }

  void selectPrinter(PrinterBluetooth printer) {
    _selectedPrinter = printer;
    _bluetoothManager.state.listen((state) async {
      switch (state) {
        case BluetoothManager.CONNECTED:
          _isConnected = true;
          print('CONNECTED STATE');
          print('CONNECTED STATE');
          break;
        case BluetoothManager.DISCONNECTED:
          _isConnected = false;
          print('DISCONNECTED STATE');
          print('DISCONNECTED STATE');
          break;
        default:
          break;
      }
      print('BluetoothManager.STATE => $state');
    });
  }

  Future<PosPrintResult> _connectBluetooth(
    List<int> bytes, {
    int timeout = 5,
  }) async {
    if (_selectedPrinter == null) {
      return Future<PosPrintResult>.value(PosPrintResult.printerNotSelected);
    } else if (_isScanning.value!) {
      return Future<PosPrintResult>.value(PosPrintResult.scanInProgress);
    } else if (_isPrinting) {
      return Future<PosPrintResult>.value(PosPrintResult.printInProgress);
    }
    // We have to rescan before connecting, otherwise we can connect only once
    await _bluetoothManager.startScan(timeout: Duration(seconds: 1));
    await _bluetoothManager.stopScan();
    // Connect
    await _bluetoothManager.connect(_selectedPrinter!._device);
    final result = await _checkConnectionState();
    return result;
  }

  Future<PosPrintResult> _writeRequest(timeout) async {
    final Completer<PosPrintResult> completer = Completer();
    if (_bufferedBytes.isNotEmpty) {
      await _writePending();
      _runDelayed(timeout).then((dynamic v) async {
        if (_isPrinting) {
          _isPrinting = false;
        }
        completer.complete(PosPrintResult.success);
      });
    }
    return completer.future;
  }

  Future<PosPrintResult> printTicket(List<int> bytes,
      {int chunkSizeBytes = 20,
      int queueSleepTimeMs = 20,
      int timeout = 5,
      int connectionTimeOut = 10}) async {
    if (bytes.isEmpty) {
      return Future<PosPrintResult>.value(PosPrintResult.ticketEmpty);
    }
    _bufferedBytes = [];
    _bufferedBytes = bytes;
    _queueSleepTimeMs = queueSleepTimeMs;
    _chunkSizeBytes = chunkSizeBytes;
    _connectionTimeOut = connectionTimeOut;
    if (_isConnected) {
      return await _writeRequest(timeout);
    } else {
      final result = await connect(bytes, timeout);
      if (result.msg == "Success") {
        return await _writeRequest(timeout);
      } else {
        return result;
      }
    }
  }

  Future<PosPrintResult> printLabel(List<int> bytes,
      {int chunkSizeBytes = 20,
      int queueSleepTimeMs = 20,
      int timeout = 5,
      int connectionTimeOut = 10}) async {
    if (bytes.isEmpty) {
      return Future<PosPrintResult>.value(PosPrintResult.ticketEmpty);
    }
    _bufferedBytes = [];
    _bufferedBytes = bytes;
    _queueSleepTimeMs = queueSleepTimeMs;
    _chunkSizeBytes = chunkSizeBytes;
    _connectionTimeOut = connectionTimeOut;
    if (_isConnected) {
      return await _writeRequest(timeout);
    } else {
      final result = await connect(bytes, timeout);
      if (result.msg == "Success") {
        return await _writeRequest(timeout);
      } else {
        return result;
      }
    }
  }

  Future<PosPrintResult> _checkConnectionState() async {
    late Timer _stateTimer;
    int _start = _connectionTimeOut;
    final Completer<PosPrintResult> completer = Completer();
    const oneSec = Duration(seconds: 1);
    _stateTimer = Timer.periodic(
      oneSec,
      (Timer timer) {
        if (_start == 0 || _isConnected) {
          timer.cancel();
          print('ENDTIME');
          print(_isConnected);
          if (_isConnected) {
            _stateTimer.cancel();
            completer.complete(PosPrintResult.success);
          } else {
            _stateTimer.cancel();
            completer.complete(PosPrintResult.timeout);
          }
        } else {
          _start--;
        }
      },
    );
    return completer.future;
  }

  Future<dynamic> connect(bytes, timeout) async {
    print("CONNECTING ON PRINT");
    print("CONNECTING ON PRINT");
    final result = await _connectBluetooth(
      bytes,
      timeout: timeout,
    );
    return result;
  }

  Future<dynamic> disconnect(timeout) async {
    final Completer<PosPrintResult> completer = Completer();
    try {
      print('PENDING DISCONNECTED');
      await Future.delayed(Duration(seconds: timeout));
      await _bluetoothManager.disconnect();
      late Timer _stateTimer;
      int _start = _connectionTimeOut;
      const oneSec = Duration(seconds: 1);
      _stateTimer = Timer.periodic(
        oneSec,
        (Timer timer) {
          print("START: $_start");
          print("STATUS: $_isConnected");
          if (_start == 0 || !_isConnected) {
            timer.cancel();
            if (!_isConnected) {
              _stateTimer.cancel();
              print('SUCCESS DISCONNECT');
              completer.complete(PosPrintResult.success);
            } else {
              _stateTimer.cancel();
              completer.complete(PosPrintResult.timeout);
            }
          } else {
            _start--;
          }
        },
      );
    } catch (err) {
      print(err);
      completer.complete(PosPrintResult.timeout);
    }

    return completer.future;
  }

  Future<void> _writePending() async {
    final len = _bufferedBytes.length;
    List<List<int>> chunks = [];
    for (var i = 0; i < len; i += _chunkSizeBytes) {
      var end = (i + _chunkSizeBytes < len) ? i + _chunkSizeBytes : len;
      chunks.add(_bufferedBytes.sublist(i, end));
    }
    _isPrinting = true;
    for (var i = 0; i < chunks.length; i += 1) {
      await _bluetoothManager.writeData(chunks[i]);
      sleep(Duration(milliseconds: _queueSleepTimeMs));
    }
    _isPrinting = false;
    _bufferedBytes = [];
  }
}
