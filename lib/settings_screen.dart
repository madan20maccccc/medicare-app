// lib/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:medicare/theme_provider.dart'; // Import ThemeProvider

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Access the ThemeProvider
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).primaryColor, // Use theme's primary color
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: <Widget>[
          // --- Theme Settings Section ---
          Card(
            margin: const EdgeInsets.only(bottom: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'App Theme',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Divider(height: 20, thickness: 1),
                  RadioListTile<ThemeMode>(
                    title: const Text('System Default'),
                    value: ThemeMode.system,
                    groupValue: themeProvider.themeMode,
                    onChanged: (ThemeMode? mode) {
                      if (mode != null) {
                        themeProvider.setThemeMode(mode);
                      }
                    },
                    activeColor: Theme.of(context).primaryColor,
                  ),
                  RadioListTile<ThemeMode>(
                    title: const Text('Light Mode'),
                    value: ThemeMode.light,
                    groupValue: themeProvider.themeMode,
                    onChanged: (ThemeMode? mode) {
                      if (mode != null) {
                        themeProvider.setThemeMode(mode);
                      }
                    },
                    activeColor: Theme.of(context).primaryColor,
                  ),
                  RadioListTile<ThemeMode>(
                    title: const Text('Dark Mode'),
                    value: ThemeMode.dark,
                    groupValue: themeProvider.themeMode,
                    onChanged: (ThemeMode? mode) {
                      if (mode != null) {
                        themeProvider.setThemeMode(mode);
                      }
                    },
                    activeColor: Theme.of(context).primaryColor,
                  ),
                ],
              ),
            ),
          ),

          // --- Account Settings Section (Placeholder) ---
          Card(
            margin: const EdgeInsets.only(bottom: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Account Settings',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Divider(height: 20, thickness: 1),
                  ListTile(
                    leading: Icon(Icons.person, color: Theme.of(context).iconTheme.color),
                    title: Text('Edit Profile', style: Theme.of(context).textTheme.bodyLarge),
                    trailing: Icon(Icons.arrow_forward_ios, size: 18, color: Theme.of(context).iconTheme.color),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Edit Profile is available from your main profile screen!')),
                      );
                      // In a real app, you might navigate to a specific edit screen here
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.lock, color: Theme.of(context).iconTheme.color),
                    title: Text('Change Password', style: Theme.of(context).textTheme.bodyLarge),
                    trailing: Icon(Icons.arrow_forward_ios, size: 18, color: Theme.of(context).iconTheme.color),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Change Password functionality coming soon!')),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // --- Notification Preferences Section (Placeholder) ---
          Card(
            margin: const EdgeInsets.only(bottom: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Notification Preferences',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Divider(height: 20, thickness: 1),
                  SwitchListTile(
                    title: Text('Receive Push Notifications', style: Theme.of(context).textTheme.bodyLarge),
                    value: true, // Example value
                    onChanged: (bool value) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Notification settings coming soon!')),
                      );
                    },
                    activeColor: Theme.of(context).primaryColor,
                  ),
                  SwitchListTile(
                    title: Text('Email Reminders', style: Theme.of(context).textTheme.bodyLarge),
                    value: false, // Example value
                    onChanged: (bool value) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Email reminder settings coming soon!')),
                      );
                    },
                    activeColor: Theme.of(context).primaryColor,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
