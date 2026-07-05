class SchoolClass {
  final int? id;
  final String name;
  final String createdAt;

  SchoolClass({
    this.id,
    required this.name,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'created_at': createdAt,
      };

  factory SchoolClass.fromMap(Map<String, dynamic> map) => SchoolClass(
        id: map['id'] as int?,
        name: map['name'] as String,
        createdAt: map['created_at'] as String,
      );
}

class Student {
  final int? id;
  final String studentId; // 4-digit
  final String name;
  final int classId;

  Student({
    this.id,
    required this.studentId,
    required this.name,
    required this.classId,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'student_id': studentId,
        'name': name,
        'class_id': classId,
      };

  factory Student.fromMap(Map<String, dynamic> map) => Student(
        id: map['id'] as int?,
        studentId: map['student_id'] as String,
        name: map['name'] as String,
        classId: map['class_id'] as int,
      );
}

class PaperTemplate {
  final int? id;
  final String name;
  final int questionCount;
  final int optionCount; // 2=判断, 4=ABCD
  final String layoutConfigJson;
  final String? standardAnswerJson;
  final String createdAt;

  PaperTemplate({
    this.id,
    required this.name,
    required this.questionCount,
    required this.optionCount,
    required this.layoutConfigJson,
    this.standardAnswerJson,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'question_count': questionCount,
        'option_count': optionCount,
        'layout_config_json': layoutConfigJson,
        'standard_answer_json': standardAnswerJson,
        'created_at': createdAt,
      };

  factory PaperTemplate.fromMap(Map<String, dynamic> map) => PaperTemplate(
        id: map['id'] as int?,
        name: map['name'] as String,
        questionCount: map['question_count'] as int,
        optionCount: map['option_count'] as int,
        layoutConfigJson: map['layout_config_json'] as String,
        standardAnswerJson: map['standard_answer_json'] as String?,
        createdAt: map['created_at'] as String,
      );
}

class ScanRecord {
  final int? id;
  final String studentId;
  final String? studentName;
  final int templateId;
  final String? className;
  final String scanTime;
  final double totalScore;
  final double maxScore;
  final String answerJson;
  final String standardAnswerJson;
  final String? imagePath;

  ScanRecord({
    this.id,
    required this.studentId,
    this.studentName,
    required this.templateId,
    this.className,
    required this.scanTime,
    required this.totalScore,
    required this.maxScore,
    required this.answerJson,
    required this.standardAnswerJson,
    this.imagePath,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'student_id': studentId,
        'student_name': studentName,
        'template_id': templateId,
        'class_name': className,
        'scan_time': scanTime,
        'total_score': totalScore,
        'max_score': maxScore,
        'answer_json': answerJson,
        'standard_answer_json': standardAnswerJson,
        'image_path': imagePath,
      };

  factory ScanRecord.fromMap(Map<String, dynamic> map) => ScanRecord(
        id: map['id'] as int?,
        studentId: map['student_id'] as String,
        studentName: map['student_name'] as String?,
        templateId: map['template_id'] as int,
        className: map['class_name'] as String?,
        scanTime: map['scan_time'] as String,
        totalScore: (map['total_score'] as num).toDouble(),
        maxScore: (map['max_score'] as num).toDouble(),
        answerJson: map['answer_json'] as String,
        standardAnswerJson: map['standard_answer_json'] as String,
        imagePath: map['image_path'] as String?,
      );
}

/// Single answer entry within answer_json
class AnswerEntry {
  final int questionIndex;
  final String answer; // "A", "B", "C", "D", or "T", "F"
  final bool correct;

  AnswerEntry({
    required this.questionIndex,
    required this.answer,
    required this.correct,
  });

  Map<String, dynamic> toJson() => {
        'q': questionIndex + 1,
        'ans': answer,
        'correct': correct,
      };

  factory AnswerEntry.fromJson(Map<String, dynamic> json) => AnswerEntry(
        questionIndex: (json['q'] as int) - 1,
        answer: json['ans'] as String,
        correct: json['correct'] as bool,
      );
}

/// Question config within template layout_config_json
class QuestionConfig {
  final int questionIndex;
  final String questionId; // 题目唯一编号
  final String knowledgeTag; // 逗号分隔知识点标签
  final String questionType; // "single" | "judge"
  final double scoreValue;

  QuestionConfig({
    required this.questionIndex,
    this.questionId = '',
    this.knowledgeTag = '',
    this.questionType = 'single',
    this.scoreValue = 1.0,
  });

  Map<String, dynamic> toJson() => {
        'qi': questionIndex,
        'qid': questionId,
        'ktag': knowledgeTag,
        'qtype': questionType,
        'score': scoreValue,
      };

  factory QuestionConfig.fromJson(Map<String, dynamic> json) => QuestionConfig(
        questionIndex: json['qi'] as int,
        questionId: json['qid'] as String? ?? '',
        knowledgeTag: json['ktag'] as String? ?? '',
        questionType: json['qtype'] as String? ?? 'single',
        scoreValue: (json['score'] as num?)?.toDouble() ?? 1.0,
      );
}
