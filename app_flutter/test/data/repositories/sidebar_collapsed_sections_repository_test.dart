import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/sidebar_collapsed_sections_repository.dart';

void main() {
  final RepoIdentity a = RepoIdentity.forWorkDir('/test/a');
  final RepoIdentity b = RepoIdentity.forWorkDir('/test/b');

  test('defaults to nothing collapsed -- every section starts open', () {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(sidebarCollapsedSectionsProvider(a)), isEmpty);
  });

  test('each repository keeps its own set', () {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(sidebarCollapsedSectionsProvider(a).notifier).state =
        <SidebarSection>{SidebarSection.tags};

    expect(
      container.read(sidebarCollapsedSectionsProvider(a)),
      <SidebarSection>{SidebarSection.tags},
    );
    expect(container.read(sidebarCollapsedSectionsProvider(b)), isEmpty);
  });
}
