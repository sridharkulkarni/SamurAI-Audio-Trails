import 'package:flutter/material.dart';

class AudioControlCard extends StatelessWidget {
  final String title;
  final String? selectedDeviceName;
  final List<Map<String, dynamic>> devices;
  final bool isCapturing;
  final bool consoleOutputEnabled;
  final VoidCallback? onDeviceSelected;
  final ValueChanged<String?>? onDeviceChanged;
  final VoidCallback onToggleCapture;
  final VoidCallback? onToggleConsoleOutput;

  const AudioControlCard({
    super.key,
    required this.title,
    this.selectedDeviceName,
    required this.devices,
    required this.isCapturing,
    required this.consoleOutputEnabled,
    this.onDeviceSelected,
    this.onDeviceChanged,
    required this.onToggleCapture,
    this.onToggleConsoleOutput,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  title == 'System Audio' ? Icons.speaker : Icons.mic,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Device Selection
            DropdownButtonFormField<String>(
              value: selectedDeviceName,
              decoration: InputDecoration(
                labelText: 'Select Device',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.audio_file),
              ),
              items: devices.map((device) {
                return DropdownMenuItem<String>(
                  value: device['name'] as String,
                  child: Text(device['name'] as String),
                );
              }).toList(),
              onChanged: onDeviceChanged,
            ),
            const SizedBox(height: 16),
            // Control Buttons
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onToggleCapture,
                    icon: Icon(isCapturing ? Icons.stop : Icons.play_arrow),
                    label: Text(isCapturing ? 'Stop' : 'Start'),
                    style: FilledButton.styleFrom(
                      backgroundColor: isCapturing
                          ? Colors.red
                          : Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Status Indicator
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isCapturing ? Colors.green : Colors.grey,
                  ),
                ),
              ],
            ),
            if (onToggleConsoleOutput != null) ...[
              const SizedBox(height: 12),
              // Save to File Toggle
              Row(
                children: [
                  Switch(
                    value: consoleOutputEnabled,
                    onChanged: (_) => onToggleConsoleOutput!(),
                  ),
                  const SizedBox(width: 8),
                  const Text('Save to File'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

