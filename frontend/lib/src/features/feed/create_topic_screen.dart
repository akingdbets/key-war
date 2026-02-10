import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'dart:io';
import 'dart:typed_data';
import '../../utils/profanity_filter.dart';

class CreateTopicScreen extends StatefulWidget {
  const CreateTopicScreen({super.key});

  @override
  State<CreateTopicScreen> createState() => _CreateTopicScreenState();
}

class _CreateTopicScreenState extends State<CreateTopicScreen> {
  final _titleController = TextEditingController();
  
  // 카테고리 (FeedScreen과 동기화)
  String _selectedCategory = '음식';
  final List<String> _categories = ['음식', '게임', '연애', '스포츠', '유머', '정치', '직장인', '패션', '기타'];

  // 투표 선택지 (기본 2개)
  final List<TextEditingController> _optionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  
  // 각 선택지의 이미지
  final List<File?> _optionImages = [null, null];
  
  // 크롭 관련 상태
  final List<CropController?> _cropControllers = [null, null];
  final List<Uint8List?> _croppingImages = [null, null];
  final List<int?> _croppingIndexes = [null, null]; // 현재 크롭 중인 선택지 인덱스
  
  final ImagePicker _imagePicker = ImagePicker();

  // Firebase 인스턴스
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  bool _isSubmitting = false; // 제출 중 상태

  @override
  void dispose() {
    _titleController.dispose();
    for (var controller in _optionControllers) {
      controller.dispose();
    }
    super.dispose();
  }
  
  // 이미지 선택 및 크롭 준비
  Future<void> _pickImage(int index) async {
    try {
      // 갤러리에서 이미지 선택
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      
      if (image == null) return;
      
      // 이미지를 바이트로 읽어서 크롭 화면에 표시
      final Uint8List imageBytes = await image.readAsBytes();
      
      setState(() {
        _croppingImages[index] = imageBytes;
        _croppingIndexes[index] = index;
        _cropControllers[index] = CropController();
      });
    } catch (e, stackTrace) {
      print("❌ 이미지 선택 에러: $e");
      print("스택 트레이스: $stackTrace");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이미지를 선택할 수 없습니다: ${e.toString()}')),
        );
      }
    }
  }
  
  // 크롭 완료 처리
  Future<void> _onCropComplete(int index, Uint8List croppedData) async {
    try {
      
      // 임시 파일로 저장
      final tempDir = Directory.systemTemp;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempFile = File('${tempDir.path}/cropped_$timestamp.jpg');
      await tempFile.writeAsBytes(croppedData);
      
      setState(() {
        _optionImages[index] = tempFile;
        _croppingImages[index] = null;
        _croppingIndexes[index] = null;
        _cropControllers[index] = null;
      });
    } catch (e) {
      print("❌ 크롭 완료 처리 에러: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이미지 저장에 실패했습니다.')),
        );
      }
    }
  }
  
  // 크롭 실행
  void _executeCrop(int index) {
    final controller = _cropControllers[index];
    if (controller != null) {
      controller.crop();
    }
  }
  
  // 크롭 취소
  void _onCropCancel(int index) {
    setState(() {
      _croppingImages[index] = null;
      _croppingIndexes[index] = null;
      _cropControllers[index] = null;
    });
  }
  
  // 이미지 제거
  void _removeImage(int index) {
    setState(() {
      _optionImages[index] = null;
    });
  }

  // 선택지 추가 기능
  void _addOption() {
    if (_optionControllers.length < 5) { // 최대 5개까지만
      setState(() {
        _optionControllers.add(TextEditingController());
        _optionImages.add(null);
        // 크롭 관련 리스트도 동기화
        _croppingImages.add(null);
        _croppingIndexes.add(null);
        _cropControllers.add(null);
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('선택지는 최대 5개까지만 가능합니다.')),
      );
    }
  }

  // 선택지 삭제 기능
  void _removeOption(int index) {
    if (_optionControllers.length > 2) { // 최소 2개는 유지
      setState(() {
        _optionControllers[index].dispose(); // 메모리 해제
        _optionControllers.removeAt(index);
        _optionImages.removeAt(index);
        // 크롭 관련 리스트도 동기화
        _croppingImages.removeAt(index);
        _croppingIndexes.removeAt(index);
        _cropControllers.removeAt(index);
      });
    }
  }

  // 등록 버튼 눌렀을 때
  Future<void> _submitTopic() async {
    // 이미 제출 중이면 무시
    if (_isSubmitting) return;

    // 유효성 검사
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('제목을 입력해주세요.')),
      );
      return;
    }
    
    // 빈 선택지가 있는지 확인
    for (var controller in _optionControllers) {
      if (controller.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('모든 선택지 내용을 입력해주세요.')),
        );
        return;
      }
    }

    // 욕설 필터링 검사 - 제목
    if (ProfanityFilter.hasProfanity(_titleController.text.trim())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('제목에 비속어가 포함되어 있습니다.')),
      );
      return;
    }

    // 욕설 필터링 검사 - 선택지
    for (var controller in _optionControllers) {
      if (ProfanityFilter.hasProfanity(controller.text.trim())) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('선택지에 비속어가 포함되어 있습니다.')),
        );
        return;
      }
    }

    // 로그인 확인
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // 1. 사용자 닉네임 가져오기
      final userDoc = await _db.collection('users').doc(user.uid).get();
      String authorNickname = '익명 유저';
      if (userDoc.exists) {
        authorNickname = userDoc.data()?['nickname'] ?? '익명 유저';
      }

      // 2. 선택지 텍스트 리스트 만들기
      final List<String> optionTexts = _optionControllers
          .map((controller) => controller.text.trim())
          .toList();
      
      // 3. 이미지 업로드 및 URL 가져오기
      final List<String?> optionImageUrls = [];
      for (int i = 0; i < _optionImages.length; i++) {
        if (_optionImages[i] != null) {
          try {
            print("📤 이미지 업로드 시작: 선택지 ${i + 1}");
            
            // 파일 존재 확인
            if (!await _optionImages[i]!.exists()) {
              throw Exception('이미지 파일을 찾을 수 없습니다.');
            }
            
            // Firebase Storage에 이미지 업로드
            final timestamp = DateTime.now().millisecondsSinceEpoch;
            final String fileName = 'topics/${user.uid}/${timestamp}_$i.jpg';
            final Reference ref = _storage.ref().child(fileName);
            
            print("📁 업로드 경로: $fileName");
            
            // 업로드 실행 (타임아웃 30초)
            final uploadTask = ref.putFile(
              _optionImages[i]!,
              SettableMetadata(
                contentType: 'image/jpeg',
                customMetadata: {'uploadedBy': user.uid},
              ),
            );
            
            // 업로드 완료 대기
            await uploadTask.timeout(
              const Duration(seconds: 30),
              onTimeout: () {
                uploadTask.cancel();
                throw Exception('이미지 업로드 시간 초과 (30초)');
              },
            );
            
            print("📤 업로드 완료, URL 가져오는 중...");
            
            // 다운로드 URL 가져오기
            final String downloadUrl = await ref.getDownloadURL().timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                throw Exception('URL 가져오기 시간 초과');
              },
            );
            
            optionImageUrls.add(downloadUrl);
            print("✅ 이미지 업로드 완료: $downloadUrl");
          } catch (e, stackTrace) {
            print("❌ 이미지 업로드 에러 (선택지 ${i + 1}): $e");
            print("스택 트레이스: $stackTrace");
            optionImageUrls.add(null);
            // 이미지 업로드 실패해도 주제 생성은 계속 진행
          }
        } else {
          optionImageUrls.add(null);
        }
      }
      
      // 이미지 업로드 실패한 것이 있으면 알림
      final failedCount = optionImageUrls.where((url) => url == null && _optionImages[optionImageUrls.indexOf(url)] != null).length;
      if (failedCount > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('일부 이미지 업로드에 실패했습니다. 텍스트만 저장됩니다.'),
            duration: const Duration(seconds: 3),
          ),
        );
      }

      // 4. 투표수 배열 초기화 (모두 0)
      final List<int> voteCounts = List.filled(optionTexts.length, 0);

      // 5. Firestore에 주제 저장
      final topicData = {
        'title': _titleController.text.trim(),
        'category': _selectedCategory,
        'authorId': user.uid,
        'authorNickname': authorNickname,
        'options': optionTexts, // 선택지 텍스트 배열
        'optionImages': optionImageUrls, // 선택지 이미지 URL 배열
        'voteCounts': voteCounts, // 투표수 배열 (초기값 모두 0)
        'totalVotes': 0, // 총 투표수
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // topics 컬렉션에 문서 추가 (자동 ID 생성)
      final docRef = await _db.collection('topics').add(topicData);

      print("✅ 주제 생성 완료: ${docRef.id}");
      print("📝 authorId: ${user.uid}");
      print("📝 주제 데이터: ${topicData['title']}");

      // 성공 메시지
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('주제가 등록되었습니다!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context); // 뒤로 가기
      }
    } catch (e) {
      print("❌ 주제 생성 에러: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('주제 등록에 실패했습니다: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inputBgColor = isDark ? const Color(0xFF2D2D3A) : Colors.grey[100];
    
    // 크롭 중인 이미지가 있는지 확인
    int? activeCropIndex;
    for (int i = 0; i < _croppingIndexes.length; i++) {
      if (_croppingIndexes[i] != null) {
        activeCropIndex = i;
        break;
      }
    }

    return Stack(
      children: [
        Scaffold(
      appBar: AppBar(
        title: const Text('새 주제 만들기', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          _isSubmitting
              ? const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : TextButton(
                  onPressed: _submitTopic,
                  child: const Text('등록', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            // 1. 카테고리 선택 (바텀 시트 방식)
            Text('카테고리', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[600])),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _showCategoryBottomSheet(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  color: inputBgColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.grey[300]!,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _selectedCategory,
                      style: TextStyle(
                        fontSize: 16,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Icon(
                      Icons.keyboard_arrow_down,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),

            // 2. 제목 입력
            Text('주제 (논쟁거리)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[600])),
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                hintText: '예: 평생 치킨무 없이 치킨 먹기 vs ...',
                filled: true,
                fillColor: inputBgColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),

            const SizedBox(height: 24),

            // 3. 투표 선택지 입력 (동적 추가 가능)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('투표 선택지', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[600])),
                TextButton.icon(
                  onPressed: _addOption,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('항목 추가'),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
              ],
            ),
            
            // 선택지 리스트
            ...List.generate(_optionControllers.length, (index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // 번호 표시 (1, 2, 3...)
                        Container(
                          width: 24, 
                          alignment: Alignment.center,
                          child: Text('${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                        ),
                        const SizedBox(width: 8),
                        // 입력창
                        Expanded(
                          child: TextField(
                            controller: _optionControllers[index],
                            decoration: InputDecoration(
                              hintText: '선택지 ${index + 1} 내용 입력',
                              filled: true,
                              fillColor: inputBgColor,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                        // 삭제 버튼 (3개 이상일 때만 보임)
                        if (_optionControllers.length > 2)
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                            onPressed: () => _removeOption(index),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // 이미지 선택 영역 (VoteScreen 크기에 맞춘 미리보기)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 이미지 미리보기 (VoteScreen과 동일한 비율: 16:9, height: 200)
                        if (_optionImages[index] != null)
                          Stack(
                            alignment: Alignment.topRight,
                            children: [
                              AspectRatio(
                                aspectRatio: 16 / 9, // 정확히 16:9 비율 유지
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.grey[300]!,
                                      width: 1,
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.file(
                                      _optionImages[index]!,
                                      width: double.infinity,
                                      height: double.infinity,
                                      fit: BoxFit.cover, // 16:9 비율로 크롭했으므로 cover 사용
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: GestureDetector(
                                  onTap: () => _removeImage(index),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      size: 20,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        else
                          AspectRatio(
                            aspectRatio: 16 / 9, // 정확히 16:9 비율 유지
                            child: GestureDetector(
                              onTap: () => _pickImage(index),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: inputBgColor,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.grey[300]!,
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_photo_alternate, color: Colors.grey[400], size: 48),
                                    const SizedBox(height: 8),
                                    Text('이미지 추가 (선택)', 
                                      style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            }),

            const SizedBox(height: 40),
            
            // 등록 버튼 (하단 고정 느낌)
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitTopic,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE91E63),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('주제 생성하기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
              ],
            ),
          ),
        ],
      ),
        ),
        // 크롭 오버레이
        if (activeCropIndex != null)
          _buildCropOverlay(activeCropIndex),
      ],
    );
  }
  
  // 카테고리 선택 바텀 시트
  void _showCategoryBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2D2D3A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 상단 핸들 바
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 제목
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Text(
                  '카테고리 선택',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              const Divider(),
              // 카테고리 리스트
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _categories.length,
                  itemBuilder: (context, index) {
                    final category = _categories[index];
                    final isSelected = _selectedCategory == category;
                    return ListTile(
                      title: Text(
                        category,
                        style: TextStyle(
                          color: isSelected
                              ? const Color(0xFFE91E63)
                              : (isDark ? Colors.white : Colors.black87),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(
                              Icons.check,
                              color: Color(0xFFE91E63),
                            )
                          : null,
                      onTap: () {
                        setState(() {
                          _selectedCategory = category;
                        });
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 크롭 오버레이 위젯
  Widget _buildCropOverlay(int index) {
    final imageBytes = _croppingImages[index];
    final controller = _cropControllers[index];
    
    if (imageBytes == null || controller == null) {
      return const SizedBox.shrink();
    }
    
    return Container(
      color: Colors.black87,
      child: SafeArea(
        child: Column(
          children: [
            // 상단 안내 문구
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.black87,
              child: Text(
                '이미지를 드래그하여 위치를 조정하세요',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.75),
                  fontSize: 14,
                  decoration: TextDecoration.none, // 밑줄 제거
                ),
                textAlign: TextAlign.center,
              ),
            ),
            // 크롭 영역
            Expanded(
              child: Crop(
                image: imageBytes,
                controller: controller,
                onCropped: (image) {
                  // CropSuccess에서 데이터 추출
                  try {
                    Uint8List? croppedBytes;
                    // crop_your_image 2.0.0: onCropped는 CropResult (CropSuccess 또는 CropFailure)를 반환
                    final cropResult = image as dynamic;
                    
                    // CropSuccess인 경우 croppedImage 속성 사용
                    if (cropResult is CropSuccess) {
                      croppedBytes = cropResult.croppedImage;
                    } else if (cropResult is Uint8List) {
                      // 직접 Uint8List인 경우
                      croppedBytes = cropResult;
                    } else {
                      // dynamic으로 처리하여 croppedImage 속성 접근 시도
                      try {
                        croppedBytes = cropResult.croppedImage as Uint8List?;
                      } catch (e) {
                        print("croppedImage 속성 접근 실패: $e");
                        // CropFailure인 경우 에러 처리
                        if (cropResult.cause != null) {
                          print("크롭 실패: ${cropResult.cause}");
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('이미지 크롭에 실패했습니다: ${cropResult.cause}')),
                            );
                          }
                          return;
                        }
                      }
                    }
                    
                    // null 체크 후 타입 확인
                    if (croppedBytes != null) {
                      _onCropComplete(index, croppedBytes);
                    } else {
                      print("크롭 데이터를 추출할 수 없습니다.");
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('이미지 크롭 데이터를 추출할 수 없습니다.')),
                        );
                      }
                    }
                  } catch (e, stackTrace) {
                    print("크롭 데이터 추출 에러: $e");
                    print("스택 트레이스: $stackTrace");
                    print("이미지 타입: ${image.runtimeType}");
                    // 에러 발생 시 사용자에게 알림
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('이미지 크롭 처리 중 오류가 발생했습니다.')),
                      );
                    }
                  }
                },
                aspectRatio: 16 / 9,
                maskColor: Colors.black54,
                radius: 0,
              ),
            ),
            // 하단 헤더 (버튼들)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFE91E63),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => _onCropCancel(index),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white.withOpacity(0.9),
                    ),
                    child: const Text(
                      '취소',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  Text(
                    '이미지 자르기',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.95),
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  TextButton(
                    onPressed: () => _executeCrop(index),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                    ),
                    child: const Text(
                      '확인',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}