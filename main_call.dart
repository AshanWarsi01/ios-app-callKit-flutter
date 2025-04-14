import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:MyGenie/api_urls.dart';
import 'package:MyGenie/call_tracking_mixin.dart';
import 'package:MyGenie/colors.dart';
import 'package:MyGenie/constants.dart';
import 'package:MyGenie/custom_button.dart';
import 'package:MyGenie/custom_snackbar.dart';
import 'package:MyGenie/dimentions.dart';
import 'package:MyGenie/loader.dart';
import 'package:MyGenie/screens/dashboard_screen.dart';
import 'package:MyGenie/shared_preference_helper.dart';
import 'package:MyGenie/models/cold_call_model.dart' as empRes;
import 'package:MyGenie/models/coldcall_logs_model.dart' as callLogs;
import 'package:MyGenie/models/more_call_log_model.dart' as moreLogs;
import 'package:MyGenie/models/random_call_model.dart' as randomCallLogs;
import 'package:MyGenie/models/random_call_details_model.dart'
    as randomCallLogsDetails;
import 'package:MyGenie/styles.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:syncfusion_flutter_datepicker/datepicker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:phone_state/phone_state.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:get/get.dart';
import 'package:MyGenie/truecaller_popup.dart';

class MainCall extends StatefulWidget {
  @override
  _MainCallState createState() => _MainCallState();
}

class _MainCallState extends State<MainCall>
    with SingleTickerProviderStateMixin, CallTrackingMixin {
  DateTime? startDate = DateTime.now();
  DateTime? endDate = DateTime.now().add(const Duration(days: 7));

  String dateWiseFilter = 'All';

  late TabController _tabController;
  bool isLoading = false;
  List<empRes.Lead> colCallList = [];
  List<callLogs.Lead> callLogsList = [];
  List<randomCallLogs.Lead> randomLogsList = [];
  String _selectedFilter = 'This Month';
  String _callLogFilter = 'Lead Call';
  final TextEditingController textController = TextEditingController();
  String currentCountryCode = '+971'; // Default country code
  bool showRangeCalender = false;
  String dateRange = '';
  int maxL = 9;

  String saveCallId = '';
  String saveLeadCallId = '';
  StreamSubscription<PhoneState>? _phoneStateSubscription;

  bool _isApiCalled = false;
  String encryptedId = '';
  TextEditingController searchController = TextEditingController();
  Timer? _debounce;
  final FocusNode searchFocusNode = FocusNode();

  void _handleTabChange() {
    if (_tabController.indexIsChanging) {
      // Clear search text and remove focus
      searchController.clear();
      searchFocusNode.unfocus();
    }
  }

  Future<void> callEntryOnGreen(countryCode) async {
    try {
      resetCallState();
      await CallTrackingMixin.platform.invokeMethod('initiateOutgoingCall');
      final fullNumber = '${countryCode + "" + textController.text}';

      // First check DND
      bool isDNDAllowed = await checkDND(fullNumber);

      // If number is in DND, stop here
      if (!isDNDAllowed) {
        showCustomSnackBar("This number is set for DND. You can't make a call",
            isError: true);
        return;
      }

      callStateManager.clearAll();
      // If DND check passes, proceed with the call
      String token = await SharedPreferencesHelper.getFcmToken();
      isLoading = true;
      showLoader(context);
      final response = await http.post(
        Uri.parse(ApiUrls.datacoldCallEntry),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(<String, String>{
          "code": countryCode,
          "mobile": textController.text.toString(),
          "stage": "cold call"
        }),
      );

      if (response.statusCode == 200) {
        await SharedPreferencesHelper.setRandomMobileCall(
            textController.text.toString());
        await SharedPreferencesHelper.setRandomMobileCallCode(countryCode);

        var data = json.decode(response.body);
        callStateManager.setCallId(data['id'].toString());
        saveCallId = data['id'].toString();
        isLoading = false;
        Navigator.pop(context);
        setState(() {});

        try {
          if (!await launchUrl(Uri.parse("tel:$fullNumber"))) {}
        } on Exception {
          showCustomSnackBar('Something went wrong');
        } catch (e) {}
      } else {
        isLoading = false;
        Navigator.pop(context);
        setState(() {});
      }
    } catch (e) {
      isLoading = false;
      Navigator.pop(context);
      setState(() {});
    }
  }

// Modified checkDND function that returns a boolean
  Future<bool> checkDND(fullNumber) async {
    try {
      String numberForDNDCheck = fullNumber;
      if (numberForDNDCheck.startsWith("+971")) {
        numberForDNDCheck = numberForDNDCheck.substring(4); // Remove +971
      } else if (numberForDNDCheck.startsWith("971")) {
        numberForDNDCheck = numberForDNDCheck.substring(3); // Remove 971
      } else if (numberForDNDCheck.startsWith("0")) {
        numberForDNDCheck = numberForDNDCheck.substring(1); // Remove 971
      }

      isLoading = true;
      showLoader(context);
      String token = await SharedPreferencesHelper.getFcmToken();
      String apiUrl = ApiUrls.checkDNDUrl;
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(<String, String>{
          "number": numberForDNDCheck,
        }),
      );

      if (response.statusCode == 200) {
        var res = json.decode(response.body);
        if (res['isDND'] == true) {
          isLoading = false;
          Navigator.pop(context); // Close loader
          return false; // Don't allow call if DND
        } else {
          isLoading = false;
          Navigator.pop(context); // Close loader
          return true; // Allow call if not DND
        }
      }
      isLoading = false;
      Navigator.pop(context); // Close loader
      return false; // Return false for any other status code
    } catch (e) {
      isLoading = false;
      Navigator.pop(context); // Close loader
      return false; // Return false on error
    }
  }

  String formatDateString(String dateString) {
    try {
      // Parse the input string to a DateTime object
      DateTime dateTime = DateTime.parse(dateString);

      // Format the DateTime object to the desired string format
      return DateFormat('dd MMM yy h:mm a').format(dateTime);
    } catch (e) {
      // Handle invalid date formats
      print("Error parsing date: $e");
      return "";
    }
  }

  @override
  Future<void> saveRandomCallDuration(String duration) async {
    print(
        "save random call Duration :- ${duration} against this id :- ${callStateManager.callId}");
    try {
      String token = await SharedPreferencesHelper.getFcmToken();
      String apiUrl = ApiUrls.saveRandomCallDuration;
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(<String, String>{
          "id": callStateManager.callId,
          "call_duration": duration
          //default : lead call ; filters : random call
        }),
      );

      if (response.statusCode == 200) {
        // Future.delayed(Duration(seconds: 1), () async {
        //   String name = "Unknown";
        //   String mobile = await SharedPreferencesHelper.getRandomMobileCall();
        //   Navigator.push(
        //     context,
        //     MaterialPageRoute(
        //         builder: (_) => PopupScreen(
        //               name: name,
        //               mobile: mobile,
        //               callTime: duration,
        //             )),
        //   );
        // });
        _isApiCalled = true;
        saveCallId = '';
        callStateManager.clearCallId();
        resetCallState();
        setState(() {});
      } else {
        setState(() {
          _isApiCalled = true;
          saveCallId = '';
          callStateManager.clearCallId();
          resetCallState();
          //showCustomSnackBar("Something went wrong",isError: true);
        });
      }
    } catch (e) {
      _isApiCalled = true;
      saveCallId = '';
      callStateManager.clearCallId();
      resetCallState();
      //showCustomSnackBar("Something went wrong",isError: true);
      setState(() {});
    }
  }

  @override
  Future<void> saveCallDuration(String duration) async {
    print(
        "save call Duration :- ${duration} against this id :- ${callStateManager.leadCallId}");
    try {
      String token = await SharedPreferencesHelper.getFcmToken();
      String apiUrl = ApiUrls.saveDuration;
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(<String, String>{
          "lead_id": callStateManager.leadCallId,
          "call_duration": duration
          //default : lead call ; filters : random call
        }),
      );
      //print(saveLeadCallId);

      if (response.statusCode == 200) {
        // Future.delayed(Duration(seconds: 1), () async {
        //   String name = await SharedPreferencesHelper.getMobileCallName();
        //   String mobile = await SharedPreferencesHelper.getMobileCall();
        //   Navigator.push(
        //     context,
        //     MaterialPageRoute(
        //         builder: (_) => PopupScreen(
        //               name: name,
        //               mobile: mobile,
        //               callTime: duration,
        //             )),
        //   );
        // });
        print(json.decode(response.body));
        _isApiCalled = true;
        saveLeadCallId = '';
        callStateManager.clearLeadCallId();
        resetCallState();
        setState(() {});
      } else {
        setState(() {
          _isApiCalled = true;
          saveLeadCallId = '';
          callStateManager.clearLeadCallId();
          resetCallState();
          //showCustomSnackBar("Something went wrong",isError: true);
        });
      }
    } catch (e) {
      _isApiCalled = true;
      saveLeadCallId = '';
      callStateManager.clearLeadCallId();
      resetCallState();
      //showCustomSnackBar("Something went wrong",isError: true);
      setState(() {});
    }
  }

  Future<void> getRandomLogs() async {
    try {
      isLoading = true;
      showLoader(context);
      String token = await SharedPreferencesHelper.getFcmToken();
      String apiUrl = ApiUrls.callLogsUrl;
      if (searchController.text.isEmpty) {
        final response = await http.post(
          Uri.parse(apiUrl),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(<String, String>{
            "call_list_type": "random call"
            //default : lead call ; filters : random call
          }),
        );

        if (response.statusCode == 200) {
          randomLogsList = randomCallLogs.RandomCallModel.fromJson(
                  json.decode(response.body))
              .leads!;
          isLoading = false;
          Navigator.pop(context);
          setState(() {});
        } else {
          setState(() {
            isLoading = false;
            Navigator.pop(context);
            showCustomSnackBar("Something went wrong", isError: true);
          });
        }
      } else {
        final response = await http.post(
          Uri.parse(apiUrl),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(<String, String>{
            "call_list_type": "random call",
            "search_value": searchController.text.toString()
            //default : lead call ; filters : random call
          }),
        );

        if (response.statusCode == 200) {
          randomLogsList = randomCallLogs.RandomCallModel.fromJson(
                  json.decode(response.body))
              .leads!;
          isLoading = false;
          Navigator.pop(context);
          setState(() {});
        } else {
          setState(() {
            isLoading = false;
            Navigator.pop(context);
            showCustomSnackBar("Something went wrong", isError: true);
          });
        }
      }
    } catch (e) {
      isLoading = false;
      Navigator.pop(context);
      showCustomSnackBar("Something went wrong", isError: true);
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String hours =
        duration.inHours > 0 ? '${twoDigits(duration.inHours)}:' : '';
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours$minutes:$seconds';
  }

  Future<void> getCallLogs() async {
    // try {
    isLoading = true;
    showLoader(context);
    String token = await SharedPreferencesHelper.getFcmToken();
    String apiUrl = ApiUrls.callLogsUrl;
    if (searchController.text.isEmpty) {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(<String, String>{
          "call_list_type": "lead call"
          //default : lead call ; filters : random call
        }),
      );
      if (response.statusCode == 200) {
        callLogsList =
            callLogs.ColdCallLogsModel.fromJson(json.decode(response.body))
                .leads;
        isLoading = false;
        Navigator.pop(context);
        setState(() {});
      } else {
        setState(() {
          isLoading = false;
          Navigator.pop(context);
          showCustomSnackBar("Something went wrong", isError: true);
        });
      }
    } else {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(<String, String>{
          "call_list_type": "lead call",
          "search_value": searchController.text.toString()
          //default : lead call ; filters : random call
        }),
      );
      if (response.statusCode == 200) {
        callLogsList =
            callLogs.ColdCallLogsModel.fromJson(json.decode(response.body))
                .leads;
        isLoading = false;
        Navigator.pop(context);
        setState(() {});
      } else {
        setState(() {
          isLoading = false;
          Navigator.pop(context);
          showCustomSnackBar("Something went wrong", isError: true);
        });
      }
    }
    // }
    // catch (e) {
    //   isLoading =  false;
    //   Navigator.pop(context);
    //   showCustomSnackBar("Something went wrong",isError: true);
    //
    // }
  }

  Future<void> getColdCalls() async {
    // try {
    isLoading = true;
    showLoader(context);
    String token = await SharedPreferencesHelper.getFcmToken();
    String apiUrl = ApiUrls.coldCallUrl;
    if (searchController.text.isEmpty) {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(<String, String>{
          "modify_date": dateWiseFilter == "All"
              ? "all"
              : dateWiseFilter == "This Month"
                  ? "this_month"
                  : dateWiseFilter == "Last Month"
                      ? "last_month"
                      : "custom", //default : all ; filters : this_month, last_month, custom
          "filter_created_at_range":
              dateRange // A range of date is send throught this parameter in a format like this :- 01-11-2024 to 30-11-2024
        }),
      );

      if (response.statusCode == 200) {
        //print(json.decode(response.body));
        colCallList =
            empRes.ColdCallModel.fromJson(json.decode(response.body)).leads;
        isLoading = false;
        Navigator.pop(context);
        setState(() {});
      } else {
        setState(() {
          isLoading = false;
          Navigator.pop(context);
          showCustomSnackBar("Something went wrong", isError: true);
        });
      }
    } else {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(<String, String>{
          "search_value": searchController.text,
          "modify_date": dateWiseFilter == "All"
              ? "all"
              : dateWiseFilter == "This Month"
                  ? "this_month"
                  : dateWiseFilter == "Last Month"
                      ? "last_month"
                      : "custom", //default : all ; filters : this_month, last_month, custom
          "filter_created_at_range":
              dateRange // A range of date is send throught this parameter in a format like this :- 01-11-2024 to 30-11-2024
        }),
      );

      if (response.statusCode == 200) {
        //print(json.decode(response.body));
        colCallList =
            empRes.ColdCallModel.fromJson(json.decode(response.body)).leads;
        isLoading = false;
        Navigator.pop(context);
        setState(() {});
      } else {
        setState(() {
          isLoading = false;
          Navigator.pop(context);
          showCustomSnackBar("Something went wrong", isError: true);
        });
      }
    }
    // }
    // catch (e) {
    //   isLoading =  false;
    //   Navigator.pop(context);
    //   showCustomSnackBar("Something went wrong",isError: true);
    //
    // }
  }

  void _showDateFilterDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Padding(
              padding:
                  const EdgeInsets.all(16.0), // Adds padding around the dialog
              child: StatefulBuilder(builder: (BuildContext context, setState) {
                return Container(
                  decoration: BoxDecoration(
                    color: ColorData.keypadColor,
                    borderRadius: BorderRadius.circular(
                        2), // Rounded corners for aesthetics
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      mainAxisSize:
                          MainAxisSize.min, // Adjust height to content
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            SizedBox(
                                width: 40), // Placeholder for spacing alignment

                            Text(
                              'Filter',
                              style: rubikMedium.copyWith(
                                color: Colors.white,
                                fontSize: 20,
                              ),
                            ),

                            GestureDetector(
                              onTap: () =>
                                  Navigator.pop(context), // Close dialog on tap
                              child: Image.asset(
                                "assets/cross.png",
                                width: 30,
                                height: 30,
                              ),
                            ),
                          ],
                        ),
                        // Subtitle
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8.0, vertical: 10.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Date Filter',
                                style: poppinsRegular.copyWith(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                              Image.asset(
                                "assets/plus.png",
                                width: 30,
                                height: 30,
                              ),
                            ],
                          ),
                        ),
                        // Options
                        _buildDateFilterMainCallOption('All', setState),
                        _buildDateFilterMainCallOption('This Month', setState),
                        _buildDateFilterMainCallOption('Last Month', setState),
                        _buildDateFilterMainCallOption('Custom', setState),
                        const SizedBox(height: 16),
                        // Calendar Grid
                        showRangeCalender ? _buildCalendarGrid() : SizedBox(),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }

  void _callLogsFilterDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Padding(
              padding:
                  const EdgeInsets.all(20.0), // Adds padding around the dialog
              child: StatefulBuilder(
                builder: (BuildContext context, setState) {
                  return Container(
                    decoration: BoxDecoration(
                      color: ColorData.keypadColor,
                      borderRadius: BorderRadius.circular(
                          2), // Rounded corners for aesthetics
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        mainAxisSize:
                            MainAxisSize.min, // Adjust height to content
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              SizedBox(
                                  width:
                                      40), // Placeholder for spacing alignment

                              Text(
                                'Filter',
                                style: rubikMedium.copyWith(
                                  color: Colors.white,
                                  fontSize: 20,
                                ),
                              ),

                              GestureDetector(
                                onTap: () => Navigator.pop(
                                    context), // Close dialog on tap
                                child: Image.asset(
                                  "assets/cross.png",
                                  width: 30,
                                  height: 30,
                                ),
                              ),
                            ],
                          ),
                          // Subtitle
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8.0, vertical: 10.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Call Type',
                                  style: poppinsRegular.copyWith(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                                Icon(Icons.add, color: Colors.white),
                              ],
                            ),
                          ),

                          // _buildDateFilterOption('All'),
                          _buildDateFilterOption('Lead Call'),
                          _buildDateFilterOption('Random Call'),
                          SizedBox(height: 10)
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  void showDialerPopup(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return Stack(
          children: [
            Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: ColorData.keypadColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  width: MediaQuery.of(context).size.width *
                      0.9, // 90% of screen width
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Phone number input row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Expanded(
                            flex: 3,
                            child: IntlPhoneField(
                              textAlign: TextAlign.center,
                              cursorColor: Colors.white,
                              dropdownTextStyle:
                                  const TextStyle(color: Colors.white),
                              readOnly: false,
                              dropdownDecoration: BoxDecoration(
                                color: Color(
                                    0xFF484747), // Dropdown background color
                                borderRadius: BorderRadius.circular(5),
                              ),
                              flagsButtonPadding:
                                  EdgeInsets.symmetric(horizontal: 5),
                              decoration: InputDecoration(
                                iconColor: Colors.white,
                                prefixIconColor: Colors.white,
                                counterText: '',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8.0),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: ColorData.lightBlack,
                                hintText: 'Enter Phone Number',
                                hintStyle: rubikRegular.copyWith(fontSize: 12),
                              ),
                              initialCountryCode: 'AE',
                              onCountryChanged: (phone) {
                                setState(() {
                                  maxL = phone.maxLength;
                                  currentCountryCode = "+" + phone.dialCode;
                                });
                              },
                              controller: textController,
                              showDropdownIcon: true,
                              style: rubikMedium,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              // Remove one character on tap
                              if (textController.text.isNotEmpty) {
                                HapticFeedback.lightImpact();
                                setState(() {
                                  textController.text = textController.text
                                      .substring(
                                          0, textController.text.length - 1);
                                });
                              }
                            },
                            onLongPress: () {
                              HapticFeedback.heavyImpact();
                              // Clear all text on long press
                              setState(() {
                                textController.clear();
                              });
                            },
                            child: Container(
                              padding: EdgeInsets.all(8.0),
                              child: Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 30.0,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Dialpad Grid
                      GridView.builder(
                        shrinkWrap: true,
                        physics: NeverScrollableScrollPhysics(),
                        itemCount: 12,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3, // 3 items per row
                          mainAxisSpacing: 5,
                          crossAxisSpacing: 10,
                          childAspectRatio: 1,
                        ),
                        itemBuilder: (context, index) {
                          String buttonText;
                          if (index == 9) {
                            buttonText = '*';
                          } else if (index == 10) {
                            buttonText = '0';
                          } else if (index == 11) {
                            buttonText = '#';
                          } else {
                            buttonText = '${index + 1}';
                          }
                          return DialButton(
                            text: buttonText,
                            onPressed: () {
                              textController.text += buttonText;
                            },
                          );
                        },
                      ),

                      SizedBox(height: 16),

                      // Call and Add Lead Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          SizedBox(width: 50), // Placeholder for spacing
                          FloatingActionButton(
                            elevation: 0.0,
                            backgroundColor: ColorData.green,
                            onPressed: () async {
                              await SharedPreferencesHelper.setRandomMobileCall(
                                  '');
                              if (textController.text.length == maxL) {
                                Navigator.pop(context);
                                callEntryOnGreen(currentCountryCode);
                              } else {
                                textController.clear();
                                Navigator.pop(context);
                                showCustomSnackBar("Invalid dial number",
                                    isError: true);
                              }
                            },
                            child: Icon(Icons.call, color: Colors.white),
                          ),
                          FloatingActionButton(
                            elevation: 0.0,
                            backgroundColor: ColorData.backGroundColor,
                            onPressed: () async {
                              String number = await SharedPreferencesHelper
                                  .getRandomMobileCall();
                              if (number.isNotEmpty && number != null) {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        DashboardScreen(indextNum: 16),
                                  ),
                                );
                              } else {
                                showCustomSnackBar(
                                  "After call you can create a lead activity.",
                                  isError: true,
                                );
                              }
                            },
                            child: Icon(Icons.add_box_outlined,
                                color: Colors.black),
                          ),
                        ],
                      ),

                      SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),

            // Close Button Positioned Below the Dialog
            Positioned(
              bottom: MediaQuery.of(context).size.height * 0.015, // Adjust position at the bottom
              left: MediaQuery.of(context).size.width / 2 - 30, // Center horizontally
              child: FloatingActionButton(
                backgroundColor: Colors.red, // Red background for close button
                onPressed: () {
                  textController.clear();
                  Navigator.pop(context); // Close the dialog
                },
                child: Icon(Icons.close, color: Colors.white, size: 30),
              ),
            ),
          ],
        );
      },
    );
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce?.cancel();

    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (_tabController.index == 0) {
        if (searchController.text.length >= 3) {
          getColdCalls();
        } else if (searchController.text.isEmpty) {
          getColdCalls();
        }
      } else if (_tabController.index == 1) {
        if (_callLogFilter == 'Lead Call') {
          if (searchController.text.length >= 3) {
            getCallLogs();
          } else if (searchController.text.isEmpty) {
            getCallLogs();
          }
        } else if (_callLogFilter == 'Random Call') {
          if (searchController.text.length >= 3) {
            getRandomLogs();
          } else if (searchController.text.isEmpty) {
            getRandomLogs();
          }
        }
      }
    });
  }

  // void showDialerPopup(BuildContext context) {
  //   showDialog(
  //     context: context,
  //     builder: (context) {
  //       return Center(
  //         child: Material(
  //           color: Colors.transparent,
  //           child: Container(
  //             padding: const EdgeInsets.all(8.0),
  //             decoration: BoxDecoration(
  //               color: ColorData.keypadColor,
  //               borderRadius: BorderRadius.circular(16),
  //             ),
  //             width: MediaQuery.of(context).size.width *
  //                 0.9, // 90% of the screen width
  //             child: Column(
  //               mainAxisSize: MainAxisSize.min,
  //               children: [
  //                 Row(
  //                   crossAxisAlignment: CrossAxisAlignment.center,
  //                   mainAxisAlignment: MainAxisAlignment.center,
  //                   children: [
  //                     Expanded(
  //                       flex: 3,
  //                       child: IntlPhoneField(
  //                         textAlign: TextAlign.center,
  //                         cursorColor: Colors.white,
  //                         dropdownTextStyle:
  //                             const TextStyle(color: Colors.white),
  //                         readOnly: false, // Set to false for testing
  //                         dropdownDecoration: BoxDecoration(
  //                           color:
  //                               Color(0xFF484747), // Dropdown background color
  //                           borderRadius: BorderRadius.circular(5),
  //                         ),
  //                         flagsButtonPadding:
  //                             EdgeInsets.symmetric(horizontal: 5),
  //                         decoration: InputDecoration(
  //                           iconColor: Colors.white,
  //                           prefixIconColor: Colors.white,
  //                           counterText: '',
  //                           border: OutlineInputBorder(
  //                             borderRadius: BorderRadius.circular(8.0),
  //                             borderSide: BorderSide.none,
  //                           ),
  //                           filled: true,
  //                           fillColor: ColorData.lightBlack,
  //                           hintText: 'Enter Phone Number',
  //                           hintStyle: rubikRegular.copyWith(fontSize: 12),
  //                         ),
  //                         initialCountryCode: 'AE',
  //                         onCountryChanged: (phone) {
  //                           setState(() {
  //                             maxL = phone.maxLength;
  //                             currentCountryCode = "+" + phone.dialCode;
  //                             //print(currentCountryCode);
  //                           });
  //                         },
  //                         controller: textController,
  //                         showDropdownIcon: true,
  //                         style: rubikMedium,
  //                       ),
  //                     ),
  //                     IconButton(
  //                       onPressed: () {
  //                         textController.clear(); // Clear the input field
  //                       },
  //                       icon: Icon(Icons.close, color: Colors.white),
  //                     ),
  //                   ],
  //                 ),
  //                 const SizedBox(height: 20),
  //                 GridView.builder(
  //                   shrinkWrap:
  //                       true, // Ensures the GridView only takes as much space as needed
  //                   physics:
  //                       NeverScrollableScrollPhysics(), // Prevents scrolling
  //                   itemCount: 12,
  //                   gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
  //                     crossAxisCount: 3, // 3 items per row
  //                     mainAxisSpacing: 5, // Reduced vertical spacing
  //                     crossAxisSpacing: 10, // Reduced horizontal spacing
  //                     childAspectRatio:
  //                         1, // Adjust the ratio to control height/width
  //                   ),
  //                   itemBuilder: (context, index) {
  //                     String buttonText;
  //                     if (index == 9) {
  //                       buttonText = '*';
  //                     } else if (index == 10) {
  //                       buttonText = '0';
  //                     } else if (index == 11) {
  //                       buttonText = '#';
  //                     } else {
  //                       buttonText = '${index + 1}';
  //                     }
  //                     return DialButton(
  //                       text: buttonText,
  //                       onPressed: () {
  //                         textController.text +=
  //                             buttonText; // Append the button text to the input
  //                       },
  //                     );
  //                   },
  //                 ),
  //                 SizedBox(height: 16),
  //                 Row(
  //                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
  //                   children: [
  //                     SizedBox(width: 50),
  //                     Padding(
  //                       padding: const EdgeInsets.only(left: 20.0),
  //                       child: FloatingActionButton(
  //                         elevation: 0.0, // Remove shadow
  //                         highlightElevation: 0.0, // No shadow when pressed
  //                         backgroundColor: ColorData.green,
  //                         onPressed: () async {
  //                           if (textController.text.toString().length == maxL) {
  //                             Navigator.pop(context);
  //                             callEntryOnGreen(currentCountryCode);
  //                           } else {
  //                             textController.clear();
  //                             Navigator.pop(context);
  //                             showCustomSnackBar("Invalid dial number",
  //                                 isError: true);
  //                           }
  //                         },
  //                         child: Icon(Icons.call, color: Colors.white),
  //                       ),
  //                     ),
  //                     Padding(
  //                       padding: const EdgeInsets.only(right: 20.0),
  //                       child: FloatingActionButton(
  //                         elevation: 0.0, // Remove shadow
  //                         highlightElevation: 0.0, // No shadow when pressed
  //                         backgroundColor: ColorData.backGroundColor,
  //                         onPressed: () async {
  //                           String number = await SharedPreferencesHelper
  //                               .getRandomMobileCall();
  //                           if (number.isNotEmpty && number != null) {
  //                             await Navigator.of(context).push(
  //                                 MaterialPageRoute(
  //                                     builder: (_) =>
  //                                         DashboardScreen(indextNum: 16)));
  //                           } else {
  //                             showCustomSnackBar(
  //                                 "After call you can create a lead activity.",
  //                                 isError: true);
  //                           }
  //                         },
  //                         child:
  //                             Icon(Icons.add_box_outlined, color: Colors.black),
  //                       ),
  //                     ),
  //                   ],
  //                 ),
  //                 SizedBox(height: 16),
  //               ],
  //             ),
  //           ),
  //         ),
  //       );
  //     },
  //   );
  // }

  Widget _buildDateFilterMainCallOption(String title, StateSetter setState) {
    return SizedBox(
      height: 40,
      child: RadioListTile<String>(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.trailing,
        fillColor: MaterialStateColor.resolveWith((states) => Colors.white),
        activeColor: Colors.white,
        value: title,
        groupValue: dateWiseFilter,
        onChanged: (value) {
          dateWiseFilter = value!;
          if (dateWiseFilter == "Custom") {
            showRangeCalender = true;
            setState;
          } else {
            showRangeCalender = false;
            getColdCalls();
            Navigator.pop(context);
          }
          setState(() {});
        },
        title: Text(
          title,
          style: poppinsRegular.copyWith(),
        ),
      ),
    );
  }

  Widget _buildDateFilterOption(String title) {
    return SizedBox(
      height: 40,
      child: RadioListTile<String>(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.trailing,
        fillColor: MaterialStateColor.resolveWith((states) => Colors.white),
        activeColor: Colors.white,
        value: title,
        groupValue: _callLogFilter,
        onChanged: (value) {
          _callLogFilter = value!;
          Navigator.pop(context);
          if (_callLogFilter == "Lead Call") {
            searchController.text = "";
            getCallLogs();
          } else {
            searchController.text = "";
            getRandomLogs();
          }
          setState(() {});
        },
        title: Text(
          title,
          style: poppinsRegular.copyWith(),
        ),
      ),
    );
  }

  Widget _buildCalendarGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SfDateRangePicker(
          headerStyle: DateRangePickerHeaderStyle(
            backgroundColor: Colors.transparent,
            textStyle: poppinsRegular.copyWith(
              color: Colors.white, // Month header text color
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          monthCellStyle: DateRangePickerMonthCellStyle(
            textStyle: poppinsRegular.copyWith(
              color: Colors.white, // Default date text color
            ),
            weekendTextStyle: poppinsRegular.copyWith(
              color: ColorData.lightGreyColor, // Weekend dates text color
            ),
            disabledDatesTextStyle: poppinsRegular.copyWith(
              color: Colors.grey, // Disabled dates text color
            ),
          ),
          monthViewSettings: DateRangePickerMonthViewSettings(
            enableSwipeSelection: true,
            viewHeaderStyle: DateRangePickerViewHeaderStyle(
              textStyle: poppinsRegular.copyWith(
                color: ColorData.lightGreyColor, // Weekday labels color
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          navigationDirection: DateRangePickerNavigationDirection.horizontal,
          selectionShape: DateRangePickerSelectionShape.rectangle,
          selectionTextStyle: poppinsRegular.copyWith(
            color: Colors.white, // Selected date text color
          ),
          rangeSelectionColor: ColorData.backGroundColor,
          selectionColor: ColorData.backGroundColor,
          onSelectionChanged: (DateRangePickerSelectionChangedArgs args) {
            if (args.value is PickerDateRange) {
              PickerDateRange range = args.value;
              String startDate =
                  DateFormat('dd-MM-yyyy').format(range.startDate!);
              String endDate = DateFormat('dd-MM-yyyy').format(range.endDate!);
              dateRange = startDate + " to " + endDate;
              //print("Selected range: $startDate to $endDate");
              setState(() {});
            }
          },
          todayHighlightColor: ColorData.backGroundColor,
          selectionMode: DateRangePickerSelectionMode.range,
          // initialSelectedRange: PickerDateRange(
          //   DateTime.now(),
          //   DateTime.now(),
          // ),
        ),
        InkWell(
            onTap: () {
              Navigator.pop(context);
              getColdCalls();
            },
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text("Apply",
                      style:
                          rubikBold.copyWith(color: ColorData.backGroundColor)),
                  SizedBox(
                    width: 10,
                  ),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: ColorData.backGroundColor,
                  )
                ],
              ),
            ))
      ],
    );
  }

  Future<void> whatsAppCallApi(String id, String number) async {
    try {
      String token = await SharedPreferencesHelper.getFcmToken();
      showLoader(context);

      final response = await http.post(
        Uri.parse(ApiUrls.coldCallWhatsAppUrl), // Replace with your API URL
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(<String, String>{
          "id": id, // required in encrypted form
          "flag": "cold-call-wp", // always
        }),
      );

      if (response.statusCode == 200) {
        var data = json.decode(response.body);

        Navigator.pop(context);
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation1, animation2) =>
                DashboardScreen(indextNum: 9),
            transitionDuration: Duration(seconds: 0),
          ),
        );

        var androidUrl =
            "whatsapp://send?phone=$number&text=Write the support, you want";
        try {
          if (Platform.isIOS) {
            if (!await launchUrl(Uri.parse(androidUrl))) {
              throw Exception('Could not launch $androidUrl');
            }
          } else {
            if (!await launchUrl(Uri.parse(androidUrl))) {
              throw Exception('Could not launch $androidUrl');
            }
          }
        } on Exception {
          showCustomSnackBar('Could not launch.');
        }

        setState(() {});
        showCustomSnackBar("Submitted Successfully", isError: false);
      } else {
        Navigator.pop(context);
        setState(() {});
        showCustomSnackBar("Something went wrong", isError: true);
      }
    } catch (e) {
      Navigator.pop(context);
      showCustomSnackBar("Something went wrong", isError: true);
      setState(() {});
    }
  }

  Future<void> RevertApi(String id) async {
    try {
      String token = await SharedPreferencesHelper.getFcmToken();
      showLoader(context);
      final response = await http.post(
        Uri.parse(ApiUrls.leadCallRevert), // Replace with your API URL
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(<String, String>{
          "id": id, // required in encrypted form
        }),
      );

      if (response.statusCode == 200) {
        print(json.decode(response.body));
        Navigator.pop(context);
        Navigator.pushReplacement(
            context,
            PageRouteBuilder(
                pageBuilder: (context, animation1, animation2) =>
                    DashboardScreen(indextNum: 9),
                transitionDuration: Duration(seconds: 0)));
        setState(() {});
        showCustomSnackBar('Lead Reverted Successfully', isError: false);
      } else {
        Navigator.pop(context);
        setState(() {});
        showCustomSnackBar("Something went wrong", isError: true);
      }
    } catch (e) {
      Navigator.pop(context);
      showCustomSnackBar("Something went wrong", isError: true);
      setState(() {});
    }
  }

  Future<void> CallApi(String id, String number, String userName) async {
    try {
      // First check DND
      bool isDNDAllowed = await checkDND(number);

      // If number is in DND, stop here
      if (!isDNDAllowed) {
        showCustomSnackBar("This number is set for DND. You can't make a call",
            isError: true);
        return;
      }
      callStateManager.clearAll();
      resetCallState();
      String token = await SharedPreferencesHelper.getFcmToken();
      showLoader(context);
      final response = await http.post(
        Uri.parse(ApiUrls.coldCallAppUrl), // Replace with your API URL
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(<String, String>{
          "id": id, // required in encrypted form
          "flag": "cold-call", // always
        }),
      );

      if (response.statusCode == 200) {
        var data = json.decode(response.body);
        await SharedPreferencesHelper.setMobileCall(number);
        await SharedPreferencesHelper.setMobileCallName(userName);
        callStateManager.setLeadCallId(data['id'].toString());
        saveLeadCallId = data['id'].toString();
        //print(saveLeadCallId);
        Navigator.pop(context);
        Navigator.pushReplacement(
            context,
            PageRouteBuilder(
                pageBuilder: (context, animation1, animation2) =>
                    DashboardScreen(indextNum: 9),
                transitionDuration: Duration(seconds: 0)));
        setState(() {});
        try {
          if (!await launchUrl(Uri.parse("tel:$number"))) {}
          print(saveLeadCallId);
        } on Exception {
          showCustomSnackBar('Something went wrong');
        } catch (e) {}
      } else {
        Navigator.pop(context);
        setState(() {});
        showCustomSnackBar("Something went wrong", isError: true);
      }
    } catch (e) {
      Navigator.pop(context);
      showCustomSnackBar("Something went wrong", isError: true);
      setState(() {});
    }
  }

  @override
  void initState() {
    _tabController = TabController(length: 2, vsync: this);
    Future.delayed(Duration.zero, () {
      getColdCalls();
      getCallLogs();
    });
    searchController.addListener(_onSearchChanged);
    _tabController.addListener(_handleTabChange);
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    searchController.removeListener(_onSearchChanged);
    searchController.dispose();
    _debounce?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: ColorData.keypadColor,
        floatingActionButton: FloatingActionButton(
            elevation: 0,
            child: Image.asset("assets/keypad.png", width: 25, height: 25),
            backgroundColor: ColorData.backGroundColor,
            onPressed: () {
              showDialerPopup(context);
            }),
        floatingActionButtonLocation: FloatingActionButtonLocation.startDocked,
        bottomSheet: Padding(padding: EdgeInsets.only(bottom: 50)),
        body: Container(
          decoration: BoxDecoration(color: ColorData.keypadColor),
          child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  PhysicalModel(
                    color: Color(0xFF332C2A), // Background color
                    elevation: 9, // Elevation value
                    borderRadius:
                        BorderRadius.circular(25), // Optional: Rounded corners
                    shadowColor: Color(0xFF332C2A),

                    child: Container(
                      height: 45,
                      decoration: BoxDecoration(
                        color: Color(0xFF332C2A),
                        borderRadius: BorderRadius.circular(
                          25.0,
                        ),
                      ),
                      child: TabBar(
                        labelStyle: poppinsRegular.copyWith(
                            fontWeight: FontWeight.w800),
                        unselectedLabelStyle: poppinsRegular.copyWith(
                            fontWeight: FontWeight.w800),
                        controller: _tabController,
                        indicator: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            25.0,
                          ),
                          color: ColorData.backGroundColor,
                        ),
                        labelColor: Colors.black,
                        unselectedLabelColor: Colors.white,
                        tabs: [
                          Tab(
                            text: 'Call Data',
                          ),
                          Tab(
                            text: 'Call Logs',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: Dimensions.paddingSizeDefault),
                  SizedBox(
                    height: 40,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: searchController,
                            focusNode: searchFocusNode,
                            cursorColor: Colors.white,
                            style: const TextStyle(color: Colors.white),
                            textCapitalization: TextCapitalization.words,
                            decoration: InputDecoration(
                              contentPadding: EdgeInsets.symmetric(
                                  vertical: 16,
                                  horizontal: 16), // Adjust padding if needed
                              filled: true,
                              fillColor: Colors.grey[900],
                              hintText: "",
                              hintStyle: const TextStyle(color: Colors.grey),
                              suffixIcon: Image.asset("assets/search.png"),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(0.0),
                                borderSide: BorderSide(
                                    color: Colors.white.withOpacity(0.5)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(0.0),
                                borderSide: BorderSide(
                                    color: Colors.white.withOpacity(0.5)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 18),
                        InkWell(
                          onTap: () {
                            _tabController.index == 0
                                ? _showDateFilterDialog(context)
                                : _callLogsFilterDialog(context);
                          },
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                    borderRadius:
                                        BorderRadius.all(Radius.circular(0)),
                                    border: Border.all(
                                        color: ColorData.whiiteColor
                                            .withOpacity(0.5),
                                        width: 1)),
                                child: Image.asset("assets/filter.png"),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 18),
                        InkWell(
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (context) => CreateLeadsDialog(),
                            );
                          },
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                                borderRadius:
                                    BorderRadius.all(Radius.circular(0)),
                                border: Border.all(
                                    color:
                                        ColorData.whiiteColor.withOpacity(0.5),
                                    width: 1)),
                            child: Image.asset("assets/plus.png"),
                          ),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: Dimensions.paddingSizeDefault),
                  // tab bar view here
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        colCallList.isNotEmpty
                            ? ListView.builder(
                                itemCount: colCallList.length,
                                itemBuilder: (context, index) {
                                  // Get the relative time
                                  String timeAgo = timeago
                                      .format(colCallList[index].createdAt);

                                  return Padding(
                                    padding: const EdgeInsets.only(
                                        top: 4.0, bottom: 4),
                                    child: SizedBox(
                                      height:
                                          MediaQuery.of(context).size.height /
                                              6,
                                      child: Card(
                                        margin: EdgeInsets.zero,
                                        color: Colors.grey[900],
                                        shape: RoundedRectangleBorder(
                                          side: BorderSide(
                                              color:
                                                  Colors.white.withOpacity(0.5),
                                              width: 1.5),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.max,
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 12.0,
                                                    bottom: 12,
                                                    left: 12),
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .spaceBetween,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .center,
                                                      children: [
                                                        Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            InkWell(
                                                              onTap: () {
                                                                setState(() {
                                                                  GlobalConstants
                                                                      .encryptedId = colCallList[
                                                                          index]
                                                                      .encryptedId;
                                                                  Navigator.of(
                                                                          context)
                                                                      .push(MaterialPageRoute(
                                                                          builder: (_) =>
                                                                              DashboardScreen(indextNum: 17)));
                                                                });
                                                              },
                                                              child: Text(
                                                                colCallList[
                                                                        index]
                                                                    .name,
                                                                style: montRegular.copyWith(
                                                                    fontSize:
                                                                        16,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600),
                                                              ),
                                                            ),
                                                            SizedBox(height: 7),
                                                            Text(
                                                              colCallList[index]
                                                                      .countryCode +
                                                                  colCallList[
                                                                          index]
                                                                      .mobile,
                                                              style: robotoRegular
                                                                  .copyWith(
                                                                      fontSize:
                                                                          12,
                                                                      color: ColorData
                                                                          .darkYellowColor),
                                                            ),
                                                          ],
                                                        ),
                                                        Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .end,
                                                          children: [
                                                            SizedBox(
                                                              height: 28,
                                                              child: Chip(
                                                                shape: RoundedRectangleBorder(
                                                                    borderRadius: BorderRadius.only(
                                                                        topRight:
                                                                            Radius.circular(
                                                                                5),
                                                                        topLeft:
                                                                            Radius.circular(
                                                                                5),
                                                                        bottomLeft:
                                                                            Radius.circular(
                                                                                5),
                                                                        bottomRight:
                                                                            Radius.circular(5))),
                                                                label: Text(
                                                                  timeAgo,
                                                                  style: rubikBold.copyWith(
                                                                      fontSize:
                                                                          10,
                                                                      color: Colors
                                                                          .black),
                                                                ),
                                                                backgroundColor:
                                                                    ColorData
                                                                        .backGroundColor,
                                                              ),
                                                            ),
                                                            SizedBox(height: 7),
                                                            Text(
                                                              colCallList[index]
                                                                  .leadsId,
                                                              style: rubikRegular
                                                                  .copyWith(
                                                                      fontSize:
                                                                          12,
                                                                      color: ColorData
                                                                          .lightGray),
                                                            ),
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                    SizedBox(height: 7),
                                                    Container(
                                                      height: 1,
                                                      color: Colors.grey
                                                          .withOpacity(0.5),
                                                    ),
                                                    SizedBox(height: 7),
                                                    /*Text(
                                                  colCallList[index].city,
                                                  style:rubikMedium,
                                                ),
                                                SizedBox(height: 10),*/

                                                    Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment.end,
                                                      children: [
                                                        Row(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .end,
                                                          children: [
                                                            InkWell(
                                                                onTap: () {
                                                                  if (colCallList[index]
                                                                              .isCalled ==
                                                                          '0' ||
                                                                      colCallList[index]
                                                                              .planToDo ==
                                                                          "whatsapp") {
                                                                    showDialog(
                                                                      context:
                                                                          context,
                                                                      builder: (context) =>
                                                                          CustomAlert(
                                                                              colCallList[index].encryptedId),
                                                                    );
                                                                  } else {
                                                                    showCustomSnackBar(
                                                                        "Please call or whatsapp first",
                                                                        isError:
                                                                            true);
                                                                  }
                                                                },
                                                                child: Image.asset(
                                                                    "assets/cross_circle.png",
                                                                    width: 20,
                                                                    height:
                                                                        20)),
                                                            SizedBox(
                                                              width: 10,
                                                            ),
                                                            InkWell(
                                                                onTap:
                                                                    () async {
                                                                  setState(() {
                                                                    if (colCallList[index].isCalled ==
                                                                            '0' ||
                                                                        colCallList[index].planToDo ==
                                                                            "whatsapp") {
                                                                      GlobalConstants
                                                                          .encryptedId = colCallList[
                                                                              index]
                                                                          .encryptedId;
                                                                      GlobalConstants
                                                                          .haveDone = colCallList[index].haveDone ==
                                                                              null
                                                                          ? ""
                                                                          : colCallList[index]
                                                                              .haveDone;
                                                                      Navigator.of(
                                                                              context)
                                                                          .push(
                                                                              MaterialPageRoute(builder: (_) => DashboardScreen(indextNum: 15)));
                                                                    } else {
                                                                      showCustomSnackBar(
                                                                          "Please call or whatsapp first",
                                                                          isError:
                                                                              true);
                                                                    }
                                                                  });
                                                                },
                                                                child:
                                                                    Image.asset(
                                                                  "assets/add-activity.png",
                                                                  width: 20,
                                                                  height: 20,
                                                                )),
                                                            SizedBox(
                                                              width: 10,
                                                            ),
                                                            InkWell(
                                                                onTap: () {
                                                                  if (colCallList[index]
                                                                              .isCalled ==
                                                                          '0' ||
                                                                      colCallList[index]
                                                                              .planToDo ==
                                                                          "whatsapp") {
                                                                    showDialog(
                                                                      context:
                                                                          context,
                                                                      builder: (context) =>
                                                                          CustomReturnAlert(
                                                                              colCallList[index].encryptedId),
                                                                    );
                                                                  } else {
                                                                    showCustomSnackBar(
                                                                        "Please call or whatsapp first",
                                                                        isError:
                                                                            true);
                                                                  }
                                                                },
                                                                child:
                                                                    Image.asset(
                                                                  "assets/curser.png",
                                                                  width: 20,
                                                                  height: 20,
                                                                )),
                                                            SizedBox(
                                                              width: 10,
                                                            ),
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              width:
                                                  Dimensions.paddingSizeDefault,
                                            ),
                                            Container(
                                              height: MediaQuery.of(context)
                                                      .size
                                                      .height /
                                                  3.8,
                                              width: 50,
                                              decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.only(
                                                          topRight:
                                                              Radius.circular(
                                                                  20),
                                                          bottomRight:
                                                              Radius.circular(
                                                                  20)),
                                                  color: Colors.white),
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  SizedBox(),
                                                  InkWell(
                                                      onTap: () async {
                                                        await whatsAppCallApi(
                                                            colCallList[index]
                                                                .encryptedId,
                                                            colCallList[index]
                                                                    .countryCode +
                                                                "" +
                                                                colCallList[
                                                                        index]
                                                                    .mobile
                                                                    .toString());
                                                      },
                                                      child: Image.asset(
                                                        "assets/whatsapp.png",
                                                        width: 24,
                                                        height: 24,
                                                      )),
                                                  const SizedBox(),
                                                  InkWell(
                                                      onTap: () async {
                                                        String no = colCallList[
                                                                    index]
                                                                .countryCode +
                                                            "" +
                                                            colCallList[index]
                                                                .mobile;
                                                        await CallApi(
                                                            colCallList[index]
                                                                .encryptedId,
                                                            no,
                                                            colCallList[index]
                                                                .name);
                                                      },
                                                      child: Image.asset(
                                                          "assets/calling.png",
                                                          width: 24,
                                                          height: 24,
                                                          color: Colors.black)),
                                                  SizedBox(),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              )
                            : Center(
                                child: Text(
                                "No data found.",
                                style: robotoRegular.copyWith(fontSize: 12),
                              )),
                        _callLogFilter == 'Lead Call'
                            ? ListView.builder(
                                itemCount: callLogsList.length,
                                itemBuilder: (context, index) {
                                  return Padding(
                                    padding: const EdgeInsets.only(
                                        top: 4.0, bottom: 4),
                                    child: SizedBox(
                                      height:
                                          MediaQuery.of(context).size.height /
                                              4.8,
                                      child: Card(
                                        margin: EdgeInsets.zero,
                                        color: Colors.grey[900],
                                        shape: RoundedRectangleBorder(
                                          side: BorderSide(
                                              color:
                                                  Colors.white.withOpacity(0.5),
                                              width: 1.5),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.max,
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 12.0,
                                                    bottom: 12,
                                                    left: 12),
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .spaceBetween,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .center,
                                                      children: [
                                                        Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(
                                                              callLogsList[
                                                                      index]
                                                                  .name
                                                                  .toString(),
                                                              style: montRegular
                                                                  .copyWith(
                                                                      fontSize:
                                                                          16,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600),
                                                            ),
                                                            SizedBox(height: 7),
                                                            Text(
                                                              callLogsList[
                                                                          index]
                                                                      .countryCode
                                                                      .toString() +
                                                                  callLogsList[
                                                                          index]
                                                                      .mobile
                                                                      .toString(),
                                                              style: robotoRegular
                                                                  .copyWith(
                                                                      fontSize:
                                                                          12,
                                                                      color: ColorData
                                                                          .darkYellowColor),
                                                            ),
                                                          ],
                                                        ),
                                                        InkWell(
                                                            onTap: () {
                                                              if (colCallList[index]
                                                                          .isCalled ==
                                                                      '0' ||
                                                                  colCallList[index]
                                                                          .planToDo ==
                                                                      "whatsapp") {
                                                                showDialog(
                                                                  context:
                                                                      context,
                                                                  builder: (context) =>
                                                                      CustomAlert(
                                                                          colCallList[index]
                                                                              .encryptedId),
                                                                );
                                                              } else {
                                                                showCustomSnackBar(
                                                                    "Please call or whatsapp first",
                                                                    isError:
                                                                        true);
                                                              }
                                                            },
                                                            child: Image.asset(
                                                              "assets/cross_circle.png",
                                                              width: 20,
                                                              height: 20,
                                                            )),
                                                      ],
                                                    ),
                                                    SizedBox(height: 10),
                                                    Text(
                                                      formatDateString(
                                                          callLogsList[index]
                                                              .callInteraction
                                                              .toString()),
                                                      style: rubikMedium,
                                                    ),
                                                    SizedBox(
                                                      height: 10,
                                                    ),
                                                    Text(
                                                      "Outgoing call " +
                                                          callLogsList[index]
                                                              .callDuration!
                                                              .split(":")
                                                              .first +
                                                          " min " +
                                                          callLogsList[index]
                                                              .callDuration!
                                                              .split(":")
                                                              .last +
                                                          " sec ",
                                                      style: rubikMedium,
                                                    ),
                                                    SizedBox(
                                                      height: 10,
                                                    ),
                                                    Align(
                                                      alignment:
                                                          Alignment.centerRight,
                                                      child: GestureDetector(
                                                        onTap: () {
                                                          showDialog(
                                                              context: context,
                                                              builder: (context) =>
                                                                  ShowCallDetailsDialog(
                                                                    id: callLogsList[
                                                                            index]
                                                                        .encryptedId
                                                                        .toString(),
                                                                    name: callLogsList[
                                                                            index]
                                                                        .name
                                                                        .toString(),
                                                                    number: callLogsList[index]
                                                                            .countryCode
                                                                            .toString() +
                                                                        callLogsList[index]
                                                                            .mobile
                                                                            .toString(),
                                                                  ));
                                                        },
                                                        child: Row(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .end,
                                                          children: [
                                                            Text("View More",
                                                                style: rubikMedium
                                                                    .copyWith(
                                                                        color: ColorData
                                                                            .backGroundColor)),
                                                            Icon(
                                                              Icons.arrow_right,
                                                              color: ColorData
                                                                  .backGroundColor,
                                                            )
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                    SizedBox(
                                                      height: 5,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              width:
                                                  Dimensions.paddingSizeDefault,
                                            ),
                                            Container(
                                              height: MediaQuery.of(context)
                                                      .size
                                                      .height /
                                                  3.8,
                                              width: 50,
                                              decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.only(
                                                          topRight:
                                                              Radius.circular(
                                                                  20),
                                                          bottomRight:
                                                              Radius.circular(
                                                                  20)),
                                                  color: Colors.white),
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  callLogsList[index]
                                                              .leadReturn ==
                                                          '0'
                                                      ? Spacer()
                                                      : SizedBox(),
                                                  InkWell(
                                                      onTap: () async {
                                                        String no = callLogsList[
                                                                    index]
                                                                .countryCode! +
                                                            "" +
                                                            callLogsList[index]
                                                                .mobile
                                                                .toString();
                                                        await CallApi(
                                                            callLogsList[index]
                                                                .encryptedId
                                                                .toString(),
                                                            no,
                                                            callLogsList[index]
                                                                    .name ??
                                                                'Unknown');
                                                      },
                                                      // onTap: () async{
                                                      //   try{
                                                      //     var contact = colCallList[index].countryCode;
                                                      //     if (!await launchUrl(Uri.parse("tel:$contact"))) {
                                                      //     }
                                                      //   } on Exception{
                                                      //     showCustomSnackBar('Something went wrong');
                                                      //   }catch(e){
                                                      //   }
                                                      // },
                                                      child: Image.asset(
                                                        "assets/calling.png",
                                                        width: 24,
                                                        height: 24,
                                                        color: Colors.black,
                                                      )),
                                                  SizedBox(),
                                                  callLogsList[index]
                                                              .leadReturn ==
                                                          '1'
                                                      ? InkWell(
                                                          onTap: () async {
                                                            await RevertApi(
                                                                callLogsList[
                                                                        index]
                                                                    .encryptedId
                                                                    .toString());
                                                          },
                                                          child: Image.asset(
                                                              "assets/curser.png",
                                                              width: 28,
                                                              height: 28,
                                                              color:
                                                                  Colors.black))
                                                      : Spacer(),
                                                  SizedBox(),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              )
                            : ListView.builder(
                                itemCount: randomLogsList.length,
                                itemBuilder: (context, index) {
                                  return Padding(
                                    padding: const EdgeInsets.only(
                                        top: 4.0, bottom: 4),
                                    child: SizedBox(
                                      height:
                                          MediaQuery.of(context).size.height /
                                              5.2,
                                      child: Card(
                                        margin: EdgeInsets.zero,
                                        color: Colors.grey[900],
                                        shape: RoundedRectangleBorder(
                                          side: BorderSide(
                                              color:
                                                  Colors.white.withOpacity(0.5),
                                              width: 1.5),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.max,
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 12.0,
                                                    bottom: 12,
                                                    left: 12),
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .spaceBetween,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .center,
                                                      children: [
                                                        Text(
                                                          randomLogsList[index]
                                                                  .countryCode
                                                                  .toString() +
                                                              randomLogsList[
                                                                      index]
                                                                  .mobileNumber
                                                                  .toString(),
                                                          style: poppinsRegular
                                                              .copyWith(
                                                                  fontSize: 16,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600),
                                                        ),
                                                        SizedBox(
                                                          height: 28,
                                                          child: Chip(
                                                            shape: RoundedRectangleBorder(
                                                                borderRadius: BorderRadius.only(
                                                                    topRight: Radius
                                                                        .circular(
                                                                            5),
                                                                    topLeft: Radius
                                                                        .circular(
                                                                            5),
                                                                    bottomLeft:
                                                                        Radius.circular(
                                                                            5),
                                                                    bottomRight:
                                                                        Radius.circular(
                                                                            5))),
                                                            label: Text(
                                                              randomLogsList[
                                                                      index]
                                                                  .leadStage!
                                                                  .name
                                                                  .toString(),
                                                              style: rubikBold
                                                                  .copyWith(
                                                                      fontSize:
                                                                          10,
                                                                      color: Colors
                                                                          .black),
                                                            ),
                                                            backgroundColor:
                                                                ColorData
                                                                    .backGroundColor,
                                                          ),
                                                        ),
                                                      ],
                                                    ),

                                                    //SizedBox(height: 7),

                                                    SizedBox(height: 7),
                                                    Text(
                                                      formatDateString(
                                                          randomLogsList[index]
                                                              .callInteraction
                                                              .toString()),
                                                      style: rubikMedium,
                                                    ),
                                                    SizedBox(height: 7),
                                                    Text(
                                                      "Outgoing call " +
                                                          randomLogsList[index]
                                                              .maxCallDuration!
                                                              .split(":")
                                                              .first +
                                                          " min " +
                                                          randomLogsList[index]
                                                              .maxCallDuration!
                                                              .split(":")
                                                              .last +
                                                          " sec ",
                                                      style: rubikMedium,
                                                    ),
                                                    // SizedBox(height: 10,),
                                                    // Text(
                                                    //   randomLogsList[index].createdAt.toString(),
                                                    //   style:rubikMedium,
                                                    // ),
                                                    SizedBox(
                                                      height: 10,
                                                    ),
                                                    Align(
                                                      alignment:
                                                          Alignment.centerRight,
                                                      child: GestureDetector(
                                                        onTap: () {
                                                          showDialog(
                                                              context: context,
                                                              builder: (context) =>
                                                                  RandomCallDetailsDialog(
                                                                      id: randomLogsList[
                                                                              index]
                                                                          .id
                                                                          .toString()));
                                                        },
                                                        child: Row(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .end,
                                                          children: [
                                                            Text("View More",
                                                                style: rubikMedium
                                                                    .copyWith(
                                                                        color: ColorData
                                                                            .backGroundColor)),
                                                            Icon(
                                                              Icons.arrow_right,
                                                              color: ColorData
                                                                  .backGroundColor,
                                                            )
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                    SizedBox(
                                                      height: 10,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              width:
                                                  Dimensions.paddingSizeDefault,
                                            ),
                                            Container(
                                              height: MediaQuery.of(context)
                                                      .size
                                                      .height /
                                                  5.2,
                                              width: 50,
                                              decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.only(
                                                          topRight:
                                                              Radius.circular(
                                                                  20),
                                                          bottomRight:
                                                              Radius.circular(
                                                                  20)),
                                                  color: Colors.white),
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  // SizedBox(),
                                                  InkWell(
                                                      onTap: () async {
                                                        String no =
                                                            randomLogsList[
                                                                    index]
                                                                .mobileNumber
                                                                .toString();
                                                        textController.text =
                                                            no;
                                                        await callEntryOnGreen(
                                                            randomLogsList[
                                                                    index]
                                                                .countryCode!);
                                                      },
                                                      child: Image.asset(
                                                        "assets/calling.png",
                                                        width: 24,
                                                        height: 24,
                                                        color: Colors.black,
                                                      )),
                                                  // SizedBox(),
                                                  // InkWell(
                                                  //     onTap:(){
                                                  //       showDialog(
                                                  //         context: context,
                                                  //         builder: (context) =>  CustomReturnAlert(randomLogsList[index].id.toString()),
                                                  //       );
                                                  //     },
                                                  //     child: Image.asset("assets/curser.png",width: 20,height: 20,color: Colors.black)),
                                                  // SizedBox(),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ],
                    ),
                  ),
                ],
              )),
        ));
  }
}

class DialButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;

  const DialButton({
    required this.text,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.only(left: 14.0, right: 14),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle, // Ensures the button stays circular
            color: ColorData.lightBlack,
          ),
          child: Center(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: poppinsRegular.copyWith(
                  fontSize: 25), // Adjust text size if needed
            ),
          ),
        ),
      ),
    );
  }
}

class CustomAlert extends StatefulWidget {
  String encryptedId;
  CustomAlert(this.encryptedId, {super.key});

  @override
  State<CustomAlert> createState() => _CustomAlertState();
}

class _CustomAlertState extends State<CustomAlert> {
  TextEditingController noteController = TextEditingController();

  Future<void> dnd() async {
    try {
      String token = await SharedPreferencesHelper.getFcmToken();
      showLoader(context);

      final response = await http.post(
        Uri.parse(ApiUrls.dndColdData), // Replace with your API URL
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(<String, String>{
          "lead_dnd_id": widget.encryptedId, // required in encrypted form
          "lead_note_txt": noteController.text // required
        }),
      );

      if (response.statusCode == 200) {
        var data = json.decode(response.body);
        Navigator.pop(context);
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation1, animation2) =>
                DashboardScreen(indextNum: 9),
            transitionDuration: Duration(seconds: 0),
          ),
        );
        setState(() {});
        showCustomSnackBar("Submitted Successfully", isError: false);
      } else {
        Navigator.pop(context);
        Navigator.pop(context);
        setState(() {});
        showCustomSnackBar("Something went wrong", isError: true);
      }
    } catch (e) {
      Navigator.pop(context);
      Navigator.pop(context);
      showCustomSnackBar("Something went wrong", isError: true);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: Container(
        decoration: BoxDecoration(
          color: ColorData.lightBlack, // Dark background
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                color: ColorData.yellowColor,
                borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12)),
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: 12.0, right: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Do not disturb",
                      style: rubikBold.copyWith(color: Colors.black),
                    ),
                    IconButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Dimensions.paddingSizeDefault),
            Padding(
              padding: const EdgeInsets.only(left: 12.0, right: 12),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                        text: 'Notes',
                        style: rubikRegular.copyWith(color: Colors.white)),
                    TextSpan(
                      text: '*',
                      style: rubikMedium.copyWith(color: Colors.red),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Dimensions.paddingSizeDefault),
            Padding(
              padding: const EdgeInsets.only(left: 12.0, right: 12),
              child: Container(
                height: 100.0,
                padding: const EdgeInsets.only(left: 12.0, right: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: TextField(
                  controller: noteController,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: "Write notes",
                    hintStyle: rubikRegular,
                  ),
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 20.0),
            Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: const Text(
                      "Cancel",
                      style: rubikMedium,
                    ),
                  ),
                  SizedBox(
                      width: 100,
                      height: 40,
                      child: CustomButton(
                          btnTxt: "Submit",
                          onTap: () {
                            dnd();
                          }))
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CustomReturnAlert extends StatefulWidget {
  String encryptedId;
  CustomReturnAlert(this.encryptedId, {super.key});

  @override
  State<CustomReturnAlert> createState() => _CustomReturnAlertState();
}

class _CustomReturnAlertState extends State<CustomReturnAlert> {
  TextEditingController noteController = TextEditingController();

  Future<void> returnCall() async {
    try {
      String token = await SharedPreferencesHelper.getFcmToken();
      showLoader(context);
      final response = await http.post(
        Uri.parse(ApiUrls.retuntColdLeadData), // Replace with your API URL
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(<String, String>{
          "lead_return_id": widget.encryptedId, // required in encrypted form
        }),
      );

      if (response.statusCode == 200) {
        var data = json.decode(response.body);
        Navigator.pop(context);
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation1, animation2) =>
                DashboardScreen(indextNum: 9),
            transitionDuration: Duration(seconds: 0),
          ),
        );
        setState(() {});
        showCustomSnackBar("Lead Returned Successfully", isError: false);
      } else {
        Navigator.pop(context);
        Navigator.pop(context);
        setState(() {});
        showCustomSnackBar("Something went wrong", isError: true);
      }
    } catch (e) {
      Navigator.pop(context);
      Navigator.pop(context);
      showCustomSnackBar("Something went wrong", isError: true);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: Container(
        decoration: BoxDecoration(
          color: ColorData.lightBlack, // Dark background
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                color: ColorData.yellowColor,
                borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12)),
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: 12.0, right: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Lead Return",
                      style: rubikBold.copyWith(color: Colors.black),
                    ),
                    IconButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Dimensions.paddingSizeDefault),

            Padding(
              padding: const EdgeInsets.only(left: 12.0, right: 12),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                        text: 'Notes',
                        style: rubikRegular.copyWith(color: Colors.white)),
                    TextSpan(
                      text: '*',
                      style: rubikMedium.copyWith(color: Colors.red),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Dimensions.paddingSizeDefault),

            Padding(
              padding: const EdgeInsets.only(left: 12.0, right: 12),
              child: Container(
                height: 100.0,
                padding: const EdgeInsets.only(left: 12.0, right: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: TextField(
                  controller: noteController,
                  //maxLines: 10,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: "Write notes",
                    hintStyle: rubikRegular,
                  ),
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 20.0),
            // Buttons
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: const Text(
                      "Cancel",
                      style: rubikMedium,
                    ),
                  ),
                  SizedBox(
                      width: 100,
                      height: 40,
                      child: CustomButton(
                        btnTxt: "Submit",
                        onTap: () {
                          returnCall();
                        },
                      ))
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RandomCallDetailsDialog extends StatefulWidget {
  String id;
  RandomCallDetailsDialog({super.key, required this.id});

  @override
  State<RandomCallDetailsDialog> createState() =>
      _RandomCallDetailsDialogState();
}

class _RandomCallDetailsDialogState extends State<RandomCallDetailsDialog> {
  List<randomCallLogsDetails.LeadCall> detailsList = [];
  late Map<String, dynamic> jsonData = {};
  dynamic leadData;
  String formatDateString(String dateString) {
    try {
      // Parse the input string to a DateTime object
      DateTime dateTime = DateTime.parse(dateString);

      // Format the DateTime object to the desired string format
      return DateFormat('dd MMM yy h:mm a').format(dateTime);
    } catch (e) {
      // Handle invalid date formats
      print("Error parsing date: $e");
      return "";
    }
  }

  Future<void> callsListApi() async {
    String token = await SharedPreferencesHelper.getFcmToken();
    String apiUrl = ApiUrls.randomCallDeatilsUrl;
    final response = await http.post(
      Uri.parse(apiUrl),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(<String, String>{
        "id": widget.id, // required in encrypted form
      }),
    );

    if (response.statusCode == 200) {
      jsonData = jsonDecode(response.body);
      detailsList = randomCallLogsDetails.RandomCallDetailsModel.fromJson(
              json.decode(response.body))
          .leadCalls!;
      leadData = randomCallLogsDetails.RandomCallDetailsModel.fromJson(
              json.decode(response.body))
          .selectedLead;
      print(leadData);
      setState(() {});
    } else {
      setState(() {
        // isLoading =  false;
        // Navigator.pop(context);
        showCustomSnackBar("Something went wrong", isError: true);
      });
    }
  }

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    callsListApi();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: ColorData.lightBlack,
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Column(
          children: [
            // Fixed Header
            Container(
              decoration: BoxDecoration(
                color: ColorData.yellowColor,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: 12.0, right: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Call logs list",
                      style: rubikBold.copyWith(color: Colors.black),
                    ),
                    IconButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ),

            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      const SizedBox(height: Dimensions.paddingSizeDefault),

                      // Top Container
                      Container(
                        height: 80,
                        width: double.infinity,
                        padding: const EdgeInsets.only(
                            left: 12.0, right: 12, top: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Text(
                                leadData != null
                                    ? leadData.mobileNumber.toString()
                                    : "",
                                style: poppinsRegular.copyWith(
                                    color: Colors.black,
                                    fontWeight: FontWeight.w800)),
                            Row(
                              children: [
                                Icon(Icons.call),
                                SizedBox(width: 7),
                                Text(
                                    leadData != null
                                        ? (leadData.countryCode.toString() +
                                            leadData.mobileNumber.toString())
                                        : "",
                                    style: poppinsRegular.copyWith(
                                        color: Colors.black,
                                        fontWeight: FontWeight.w400))
                              ],
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 10),

                      // List Items
                      ListView.builder(
                        physics:
                            NeverScrollableScrollPhysics(), // Important: Disable ListView scrolling
                        shrinkWrap: true,
                        itemCount: detailsList.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0, bottom: 8),
                            child: Container(
                              height: 80,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              child: ListTile(
                                title: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        formatDateString(detailsList[index]
                                            .createdAt
                                            .toString()),
                                        style: poppinsRegular.copyWith(
                                            color: Colors.black,
                                            fontWeight: FontWeight.w800)),
                                    Row(children: [
                                      Icon(Icons.call, color: Colors.black),
                                      SizedBox(width: 7),
                                      Text(
                                          leadData.countryCode.toString() +
                                              leadData.mobileNumber.toString(),
                                          style: poppinsRegular.copyWith(
                                              color: Colors.black,
                                              fontWeight: FontWeight.w400))
                                    ]),
                                    Row(
                                      children: [
                                        Text(
                                            "Outgoing call ${detailsList[index].callDuration!.split(":").first} min ${detailsList[index].callDuration!.split(":").last} sec",
                                            style: poppinsRegular.copyWith(
                                                color: Colors.black,
                                                fontWeight: FontWeight.w400)),
                                      ],
                                    )
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20.0),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ShowCallDetailsDialog extends StatefulWidget {
  String id;
  String name;
  String number;
  ShowCallDetailsDialog(
      {super.key, required this.id, required this.number, required this.name});

  @override
  State<ShowCallDetailsDialog> createState() => _ShowCallDetailsDialogState();
}

class _ShowCallDetailsDialogState extends State<ShowCallDetailsDialog> {
  List<moreLogs.LeadCall> callLogsList = [];
  late Map<String, dynamic> jsonData = {};
  dynamic? leadData = null;

  Future<void> callsListApi() async {
    String token = await SharedPreferencesHelper.getFcmToken();
    String apiUrl = ApiUrls.moreCallLogsUrl;
    final response = await http.post(
      Uri.parse(apiUrl),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(<String, String>{
        "id": widget.id, // required in encrypted form
      }),
    );

    if (response.statusCode == 200) {
      jsonData = jsonDecode(response.body);
      print(jsonData);
      leadData =
          await moreLogs.MoreCallLogModel.fromJson(json.decode(response.body))
              .selectedLead;
      callLogsList =
          await moreLogs.MoreCallLogModel.fromJson(json.decode(response.body))
              .leadCalls;
      print(leadData);
      // Navigator.pop(context);
      setState(() {});
    } else {
      setState(() {
        // isLoading =  false;
        // Navigator.pop(context);
        showCustomSnackBar("Something went wrong", isError: true);
      });
    }
  }

  String formatDateString(String dateString) {
    try {
      // Parse the input string to a DateTime object
      DateTime dateTime = DateTime.parse(dateString);

      // Format the DateTime object to the desired string format
      return DateFormat('dd MMM yy h:mm a').format(dateTime);
    } catch (e) {
      // Handle invalid date formats
      print("Error parsing date: $e");
      return "";
    }
  }

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    callsListApi();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: ColorData.lightBlack, // Dark background
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                color: ColorData.yellowColor,
                borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12)),
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: 12.0, right: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Call logs list",
                      style: rubikBold.copyWith(color: Colors.black),
                    ),
                    IconButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      const SizedBox(height: Dimensions.paddingSizeDefault),
                      // Top Container
                      Container(
                        height: 80,
                        width: double.infinity,
                        padding: const EdgeInsets.only(
                            left: 12.0, right: 12, top: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Text(widget.name,
                                style: montRegular.copyWith(
                                    color: Colors.black,
                                    fontWeight: FontWeight.w800)),
                            Row(children: [
                              Icon(Icons.call),
                              SizedBox(
                                width: 7,
                              ),
                              Text(widget.number,
                                  style: poppinsRegular.copyWith(
                                      color: Colors.black,
                                      fontWeight: FontWeight.w400))
                            ]),
                          ],
                        ),
                      ),
                      SizedBox(height: 10),

                      // List Items
                      ListView.builder(
                        physics:
                            NeverScrollableScrollPhysics(), // Important: Disable ListView scrolling
                        shrinkWrap: true,
                        itemCount: callLogsList.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0, bottom: 8),
                            child: Container(
                              height: 80,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              child: ListTile(
                                title: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        formatDateString(callLogsList[index]
                                            .createdAt
                                            .toString()),
                                        style: poppinsRegular.copyWith(
                                            color: Colors.black,
                                            fontWeight: FontWeight.w800)),
                                    Row(children: [
                                      Icon(
                                        Icons.call,
                                        color: Colors.black,
                                      ),
                                      SizedBox(
                                        width: 7,
                                      ),
                                      Text(widget.number,
                                          style: poppinsRegular.copyWith(
                                              color: Colors.black,
                                              fontWeight: FontWeight.w400))
                                    ]),
                                    Row(children: [
                                      SizedBox(
                                        width: 7,
                                      ),
                                      Text(
                                          "Outgoing Call " +
                                              callLogsList[index]
                                                  .callDuration!
                                                  .split(':')
                                                  .first +
                                              " min " +
                                              callLogsList[index]
                                                  .callDuration!
                                                  .split(':')
                                                  .last +
                                              " sec ",
                                          style: poppinsRegular.copyWith(
                                              color: Colors.black,
                                              fontWeight: FontWeight.w400))
                                    ]),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20.0),
                    ],
                  ),
                ),
              ),
            ),
            // const SizedBox(height: Dimensions.paddingSizeDefault),
            // Padding(
            //   padding: const EdgeInsets.only(left: 12.0, right: 12),
            //   child: Column(
            //     crossAxisAlignment: CrossAxisAlignment.start,
            //     mainAxisAlignment: MainAxisAlignment.start,
            //     children: [
            //       Container(
            //         height: 80,
            //         width: double.infinity,
            //         padding:
            //             const EdgeInsets.only(left: 12.0, right: 12, top: 8),
            //         decoration: BoxDecoration(
            //           color: Colors.white.withOpacity(0.5),
            //           borderRadius: BorderRadius.circular(8.0),
            //         ),
            //         child: Column(
            //           crossAxisAlignment: CrossAxisAlignment.start,
            //           mainAxisAlignment: MainAxisAlignment.start,
            //           children: [
            //             Text(leadData != null ? leadData.name.toString() : "",
            //                 style: montRegular.copyWith(
            //                     color: Colors.black,
            //                     fontWeight: FontWeight.w800)),
            //             Row(children: [
            //               Icon(Icons.call),
            //               SizedBox(
            //                 width: 7,
            //               ),
            //               Text(
            //                   leadData != null
            //                       ? (leadData.countryCode.toString() +
            //                           leadData.mobile.toString())
            //                       : "",
            //                   style: poppinsRegular.copyWith(
            //                       color: Colors.black,
            //                       fontWeight: FontWeight.w400))
            //             ]),
            //           ],
            //         ),
            //       ),
            //       SizedBox(height: 10),
            //       ListView.builder(
            //         shrinkWrap: true,
            //         itemCount: callLogsList.length,
            //         itemBuilder: (context, index) {
            //           return Padding(
            //             padding: const EdgeInsets.only(top: 8.0, bottom: 8),
            //             child: Container(
            //               height: 80,
            //               width: double.infinity,
            //               decoration: BoxDecoration(
            //                 color: Colors.white.withOpacity(0.5),
            //                 borderRadius: BorderRadius.circular(8.0),
            //               ),
            //               child: ListTile(
            //                 title: Column(
            //                   mainAxisAlignment: MainAxisAlignment.center,
            //                   crossAxisAlignment: CrossAxisAlignment.start,
            //                   children: [
            //                     Text(
            //                         formatDateString(callLogsList[index]
            //                             .createdAt
            //                             .toString()),
            //                         style: poppinsRegular.copyWith(
            //                             color: Colors.black,
            //                             fontWeight: FontWeight.w800)),
            //                     Row(children: [
            //                       Icon(
            //                         Icons.call,
            //                         color: Colors.black,
            //                       ),
            //                       SizedBox(
            //                         width: 7,
            //                       ),
            //                       Text(
            //                           leadData.countryCode.toString() +
            //                               leadData.mobile.toString(),
            //                           style: poppinsRegular.copyWith(
            //                               color: Colors.black,
            //                               fontWeight: FontWeight.w400))
            //                     ]),
            //                     Row(children: [
            //                       SizedBox(
            //                         width: 7,
            //                       ),
            //                       Text(
            //                           "Outgoing Call " +
            //                               callLogsList[index]
            //                                   .callDuration!
            //                                   .split(':')
            //                                   .first +
            //                               " min " +
            //                               callLogsList[index]
            //                                   .callDuration!
            //                                   .split(':')
            //                                   .last +
            //                               " sec ",
            //                           style: poppinsRegular.copyWith(
            //                               color: Colors.black,
            //                               fontWeight: FontWeight.w400))
            //                     ]),
            //                   ],
            //                 ),
            //               ),
            //             ),
            //           );
            //         },
            //       )
            //     ],
            //   ),
            // ),
            // const SizedBox(height: 20.0),
          ],
        ),
      ),
    );
  }
}

class CreateLeadsDialog extends StatefulWidget {
  const CreateLeadsDialog({super.key});

  @override
  State<CreateLeadsDialog> createState() => _CreateLeadsDialogState();
}

class _CreateLeadsDialogState extends State<CreateLeadsDialog> {
  TextEditingController nameController = TextEditingController();
  TextEditingController phoneController = TextEditingController();
  TextEditingController emailController = TextEditingController();
  TextEditingController cityController = TextEditingController();
  TextEditingController buggetController = TextEditingController();
  String countryCode = "+971";
  bool isLoading = false;

  Future<void> storeColdLeadReq(String name, String email, String phone,
      String code, String city, String bugget) async {
    try {
      String token = await SharedPreferencesHelper.getFcmToken();
      isLoading = true;
      showLoader(context);
      final response = await http.post(
        Uri.parse(ApiUrls.storeColdLead), // Replace with your API URL
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(<String, String>{
          "name": name, // required
          "email": email,
          "phone_no": phone, // required
          "country_code": countryCode,
          "city": city,
          "budget": bugget,
        }),
      );

      if (response.statusCode == 200) {
        var data = json.decode(response.body);
        isLoading = false;
        Navigator.pop(context);
        Navigator.pop(context);
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation1, animation2) =>
                DashboardScreen(indextNum: 9),
            transitionDuration: Duration(seconds: 0),
          ),
        );
        setState(() {});
        showCustomSnackBar("Submitted Successfully.", isError: false);
      } else {
        isLoading = false;
        Navigator.pop(context);
        Navigator.pop(context);
        showCustomSnackBar("Something went wrong", isError: true);
        setState(() {});
      }
    } catch (e) {
      isLoading = false;
      Navigator.pop(context);
      Navigator.pop(context);
      showCustomSnackBar("Something went wrong", isError: true);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: Container(
        decoration: BoxDecoration(
          color: ColorData.lightBlack, // Dark background
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: ColorData.yellowColor,
                  borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12)),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(left: 12.0, right: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Cold Lead Create",
                        style: rubikBold.copyWith(color: Colors.black),
                      ),
                      IconButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Dimensions.paddingSizeDefault),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                          text: 'Name',
                          style: robotoRegular.copyWith(color: Colors.white)),
                      TextSpan(
                        text: '*',
                        style: robotoRegular.copyWith(color: Colors.red),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Container(
                  padding: const EdgeInsets.only(left: 12.0, right: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey, // Grey input field background
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: TextField(
                    controller: nameController,
                    style: robotoRegular.copyWith(color: Colors.black),
                    decoration: InputDecoration(
                      border: InputBorder.none, // Removes the default underline
                      hintText: '', // Placeholder text
                      hintStyle:
                          robotoRegular.copyWith(color: ColorData.whiiteColor),
                    ),
                    cursorColor: Colors.white, // White cursor
                  ),
                ),
              ),
              const SizedBox(height: Dimensions.paddingSizeDefault),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                          text: 'Phone Number',
                          style: robotoRegular.copyWith(color: Colors.white)),
                      TextSpan(
                        text: '*',
                        style: robotoRegular.copyWith(color: Colors.red),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Container(
                  padding: const EdgeInsets.only(left: 0.0, right: 0),
                  decoration: BoxDecoration(
                    color: Colors.grey, // Grey input field background
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: 2,
                        child: IntlPhoneField(
                          readOnly: false, // Set to false for testing
                          decoration: InputDecoration(
                            iconColor: Colors.white,
                            prefixIconColor: Colors.white,
                            counterText: '',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8.0),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            hintText: '',
                            hintStyle: robotoRegular,
                          ),
                          initialCountryCode: 'AE',
                          onCountryChanged: (phone) {
                            setState(() {
                              countryCode = "+" + phone.dialCode;
                            });
                          },
                          controller: phoneController,
                          showDropdownIcon: true,
                          style: robotoRegular.copyWith(color: Colors.black),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Dimensions.paddingSizeDefault),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                          text: 'Email',
                          style: robotoRegular.copyWith(color: Colors.white)),
                      /* TextSpan(
                        text: '*',
                        style: robotoRegular.copyWith(color: Colors.red),
                      ),*/
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Container(
                  padding: const EdgeInsets.only(left: 12.0, right: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey, // Grey input field background
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: TextField(
                    controller: emailController,
                    style: robotoRegular.copyWith(color: Colors.black),
                    decoration: InputDecoration(
                      border: InputBorder.none, // Removes the default underline
                      hintText: '', // Placeholder text
                      hintStyle:
                          robotoRegular.copyWith(color: ColorData.whiiteColor),
                    ),
                    cursorColor: Colors.white, // White cursor
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                          text: 'City',
                          style: robotoRegular.copyWith(color: Colors.white)),
                      /* TextSpan(
                        text: '*',
                        style: robotoRegular.copyWith(color: Colors.red),
                      ),*/
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Container(
                  padding: const EdgeInsets.only(left: 12.0, right: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey, // Grey input field background
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: TextField(
                    controller: cityController,
                    style: robotoRegular.copyWith(color: Colors.black),
                    decoration: InputDecoration(
                      border: InputBorder.none, // Removes the default underline
                      hintText: '', // Placeholder text
                      hintStyle:
                          poppinsRegular.copyWith(color: ColorData.whiiteColor),
                    ),
                    cursorColor: Colors.white, // White cursor
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                          text: 'Budget',
                          style: robotoRegular.copyWith(color: Colors.white)),
                      /* TextSpan(
                        text: '*',
                        style: rubikMedium.copyWith(color: Colors.red),
                      ),*/
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Container(
                  padding: const EdgeInsets.only(left: 12.0, right: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey, // Grey input field background
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: TextField(
                    controller: buggetController,
                    style: robotoRegular.copyWith(color: Colors.black),
                    decoration: InputDecoration(
                      border: InputBorder.none, // Removes the default underline
                      hintText: '', // Placeholder text
                      hintStyle:
                          poppinsRegular.copyWith(color: ColorData.whiiteColor),
                    ),
                    cursorColor: Colors.white, // White cursor
                  ),
                ),
              ),
              const SizedBox(height: Dimensions.paddingSizeDefault),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: const Text(
                        "Cancel",
                        style: rubikMedium,
                      ),
                    ),
                    SizedBox(
                        width: 100,
                        height: 30,
                        child: CustomButton(
                          btnTxt: "Submit",
                          onTap: () {
                            if (nameController.text.toString().isEmpty) {
                              showCustomSnackBar("Enter name");
                              Navigator.pop(context);
                              return;
                            }
                            if (phoneController.text.toString().isEmpty) {
                              showCustomSnackBar("Enter phone number");
                              Navigator.pop(context);
                              return;
                            }
                            storeColdLeadReq(
                              nameController.text.toString(),
                              emailController.text.toString(),
                              phoneController.text.toString(),
                              countryCode,
                              cityController.text.toString(),
                              buggetController.text.toString(),
                            );
                          },
                        ))
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
