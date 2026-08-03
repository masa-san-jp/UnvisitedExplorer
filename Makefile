.PHONY: generate project test

# プロジェクト生成のみ。CI と人間で共通の入口。
generate:
	bash ./scripts/bootstrap.sh

# 生成して Xcode で開く。
project: generate
	open UnvisitedExplorer.xcodeproj

test: generate
	bash ./scripts/test.sh
