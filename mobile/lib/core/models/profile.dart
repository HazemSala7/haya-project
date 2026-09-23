import 'json.dart';

/// The three kinds of people who sign in, spelled as `App\Enums\Role` spells
/// them. Parsed into an enum with an explicit unknown case rather than
/// compared as strings at each screen: a typo would fail open, and failing
/// open here shows a family the office's screens.
enum AppRole {
  admin('admin'),
  specialist('specialist'),
  guardian('guardian'),

  /// A role this build has never heard of — a newer server. No permissions.
  unknown('');

  const AppRole(this.wire);

  final String wire;

  static AppRole parse(String? value) =>
      AppRole.values.firstWhere((role) => role.wire == value, orElse: () => AppRole.unknown);

  bool get isStaff => this == admin || this == specialist;
}

/// A child a guardian's login opens, as the profile lists them.
class LinkedChild {
  const LinkedChild({
    required this.id,
    required this.name,
    required this.fileNumber,
    required this.status,
    required this.relation,
  });

  final int id;
  final String name;
  final String fileNumber;
  final String status;
  final String relation;

  factory LinkedChild.fromJson(Map<String, dynamic> json) => LinkedChild(
        id: J.int0(json['id']),
        name: J.s(json['name']),
        fileNumber: J.s(json['file_number']),
        status: J.s(json['status']),
        relation: J.s(json['relation']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'file_number': fileNumber,
        'status': status,
        'relation': relation,
      };
}

/// Who is signed in — `GET /auth/me`.
class Profile {
  const Profile({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.roleLabel,
    this.phone,
    this.title,
    this.specialty,
    this.specialtyLabel,
    this.children = const [],
  });

  final int id;
  final String name;
  final String email;
  final String? phone;
  final AppRole role;
  final String roleLabel;
  final String? title;
  final String? specialty;
  final String? specialtyLabel;

  /// Guardians only — every child this login opens.
  final List<LinkedChild> children;

  bool get isAdmin => role == AppRole.admin;
  bool get isSpecialist => role == AppRole.specialist;
  bool get isGuardian => role == AppRole.guardian;
  bool get isStaff => role.isStaff;

  /// What goes under the name: her title if she has one, otherwise the role.
  String get subtitle => title ?? specialtyLabel ?? roleLabel;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: J.int0(json['id']),
        name: J.s(json['name']),
        email: J.s(json['email']),
        phone: J.str(json['phone']),
        role: AppRole.parse(J.str(json['role'])),
        roleLabel: J.s(json['role_label']),
        title: J.str(json['title']),
        specialty: J.str(json['specialty']),
        specialtyLabel: J.str(json['specialty_label']),
        children: J.list(json['children'], LinkedChild.fromJson),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'phone': phone,
        'role': role.wire,
        'role_label': roleLabel,
        'title': title,
        'specialty': specialty,
        'specialty_label': specialtyLabel,
        'children': children.map((c) => c.toJson()).toList(),
      };
}
