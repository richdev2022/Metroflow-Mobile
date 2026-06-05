import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../services/api.dart';
import '../theme/app_theme.dart';

class BusinessKycScreen extends StatefulWidget {
  const BusinessKycScreen({super.key});

  @override
  State<BusinessKycScreen> createState() => _BusinessKycScreenState();
}

class _BusinessKycScreenState extends State<BusinessKycScreen> {
  final _countryController = TextEditingController();
  final _stateController = TextEditingController();
  final _cityController = TextEditingController();
  final _streetController = TextEditingController();
  final _houseNumberController = TextEditingController();
  XFile? _proofFile;
  bool _isLoading = false;

  @override
  void dispose() {
    _countryController.dispose();
    _stateController.dispose();
    _cityController.dispose();
    _streetController.dispose();
    _houseNumberController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final ImagePicker picker = ImagePicker();
    final XFile? file = await picker.pickImage(source: ImageSource.gallery);
    if (file != null) {
      setState(() => _proofFile = file);
    }
  }

  Future<void> _handleSubmit() async {
    final country = _countryController.text.trim();
    final state = _stateController.text.trim();
    final city = _cityController.text.trim();
    final street = _streetController.text.trim();
    final houseNumber = _houseNumberController.text.trim();

    if (country.isEmpty ||
        state.isEmpty ||
        city.isEmpty ||
        street.isEmpty ||
        houseNumber.isEmpty ||
        _proofFile == null) {
      Fluttertoast.showToast(msg: 'Please fill all fields and upload proof of address');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final api = ApiService();
      await api.submitBusinessKyc({
        'country': country,
        'state': state,
        'city': city,
        'street': street,
        'house_number': houseNumber,
      }, proofFile: _proofFile);
      Fluttertoast.showToast(msg: 'Your business KYC has been submitted for review.');
      if (mounted) context.go('/main');
    } catch (e) {
      Fluttertoast.showToast(
        msg: e.toString().replaceAll('Exception: ', ''),
        backgroundColor: AppColors.error,
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextButton(
                onPressed: () => context.go('/kyc-otp'),
                child: const Text('\u2190 Back', style: TextStyle(fontSize: 16, color: Color(0xFF1e40af))),
              ),
              const SizedBox(height: 24),
              const Text('Business KYC Verification',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF1e40af))),
              const SizedBox(height: 8),
              const Text(
                'Provide your business address and proof of address document',
                style: TextStyle(fontSize: 16, color: Color(0xFF6b7280), height: 1.5),
              ),
              const SizedBox(height: 32),
              _buildField('Country', _countryController, hint: 'Nigeria'),
              _buildField('State', _stateController, hint: 'Lagos'),
              _buildField('City', _cityController, hint: 'Lagos'),
              _buildField('Street', _streetController, hint: 'Adeola Odeku Street'),
              _buildField('House Number', _houseNumberController, hint: '123', isNumber: true),
              const SizedBox(height: 16),
              InkWell(
                onTap: _pickFile,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF1e40af), width: 2, style: BorderStyle.solid),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _proofFile != null ? '\u{1F4C4} ${_proofFile!.name}' : 'Upload Proof of Address',
                        style: const TextStyle(color: Color(0xFF1e40af), fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _proofFile != null ? 'Tap to change file' : '(Utility Bill or Bank Statement)',
                        style: const TextStyle(color: Color(0xFF6b7280), fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isLoading ? null : _handleSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1e40af),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(_isLoading ? 'Submitting...' : 'Submit for Review',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, {String? hint, bool isNumber = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            keyboardType: isNumber ? TextInputType.number : TextInputType.text,
            decoration: InputDecoration(
              hintText: hint,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
        ],
      ),
    );
  }
}
