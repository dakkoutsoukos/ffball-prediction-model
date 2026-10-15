"""Every page renders on the synthetic fixture repo (no R, no real data), shows its labels, and starts no job."""
import pytest
import streamlit as st
from streamlit.testing.v1 import AppTest

from conftest import UI

PAGES = ["views/home.py", "views/players.py", "views/compare.py", "views/trade.py", "views/lineup.py", "views/waivers.py",
         "views/outlook.py", "views/draft.py", "views/research.py", "views/operations.py", "views/help.py"]


@pytest.fixture
def app(repo_root, monkeypatch):
    monkeypatch.setenv("FFUI_REPO", str(repo_root))
    monkeypatch.setenv("FFUI_DEMO", "1")
    st.cache_resource.clear()
    st.cache_data.clear()
    yield
    st.cache_resource.clear()
    st.cache_data.clear()


def run_page(page: str) -> AppTest:
    at = AppTest.from_file(str(UI / "app.py"), default_timeout=60)
    at.run()
    at.switch_page(page)
    at.run()
    return at


@pytest.mark.parametrize("page", PAGES)
def test_page_renders_without_exceptions(app, repo_root, page):
    at = run_page(page)
    assert not at.exception, [e.message for e in at.exception]
    assert any("DEMONSTRATION DATA" in e.value for e in at.error), "demo banner missing"
    assert not (repo_root / "data/archive/ui_cache/jobs").exists(), "opening a page must not start a job"


def test_home_shows_shadow_odds_and_ledgered_board(app):
    at = run_page("views/home.py")
    md = " ".join(m.value for m in at.markdown)
    assert "Waiver board" in md
    assert any(m.label == "P(playoffs)" and m.value == "60.0%" for m in at.metric)


def test_research_shows_seal_notice(app):
    at = run_page("views/research.py")
    assert any("sealed" in i.value for i in at.info)


def test_decision_pages_wait_for_explicit_context_load(app):
    for p in ["views/trade.py", "views/lineup.py", "views/outlook.py"]:
        at = run_page(p)
        assert any(b.label == "Load league context" for b in at.button)


def test_players_table_and_stale_warning(app):
    at = run_page("views/players.py")
    assert len(at.dataframe) >= 1 and len(at.dataframe[0].value) == 5
    assert any("hours old" in w.value for w in at.warning)
