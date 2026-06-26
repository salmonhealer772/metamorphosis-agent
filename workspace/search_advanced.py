#!/usr/bin/env python3
"""
Advanced Web Search Tool - Enhanced version with multiple API sources
Combines Wikipedia, Wikidata, and web scraping for comprehensive results
"""

import urllib.request
import urllib.parse
import json
import ssl
import re
from datetime import datetime
from html.parser import HTMLParser

class SearchResultParser(HTMLParser):
    """Parse HTML search results from various sources"""
    
    def __init__(self):
        super().__init__()
        self.results = []
        self.current_result = {}
        self.in_result = False
        self.in_title = False
        self.in_url = False
        self.in_snippet = False
    
    def handle_starttag(self, tag, attrs):
        attrs_dict = dict(attrs)
        
        if tag == 'a' and 'class' in attrs_dict:
            if 'result__main' in attrs_dict['class'] or 'searchresult' in attrs_dict['class']:
                self.in_result = True
                self.current_result = {'url': attrs_dict.get('href', '')}
    
    def handle_data(self, data):
        if self.in_result:
            if data.strip():
                if 'title' not in self.current_result:
                    self.current_result['title'] = data.strip()[:100]

def search_wikipedia(query, count=5):
    """Search Wikipedia API for articles"""
    base_url = "https://en.wikipedia.org/w/api.php"
    params = {
        'action': 'query',
        'list': 'search',
        'srsearch': query,
        'format': 'json',
        'srlimit': count,
        'origin': '*'
    }
    
    url = f"{base_url}?{urllib.parse.urlencode(params)}"
    
    try:
        ssl_context = ssl.create_default_context()
        request = urllib.request.Request(
            url,
            headers={'User-Agent': 'Mozilla/5.0 (OpenClaw Search Tool)'}
        )
        
        with urllib.request.urlopen(request, context=ssl_context, timeout=15) as response:
            data = json.loads(response.read().decode('utf-8'))
            
            results = []
            for page in data.get('query', {}).get('search', []):
                result = {
                    'title': page.get('title', 'N/A'),
                    'summary': page.get('snippet', 'No description') + '...',
                    'url': f"https://en.wikipedia.org/wiki/{page.get('title', '')}",
                    'source': 'Wikipedia',
                    'type': 'article'
                }
                results.append(result)
            
            return results
            
    except Exception as e:
        return [{'error': f'Wikipedia search failed: {str(e)}'}]

def search_wikidata(query, count=5):
    """Search Wikidata for structured knowledge"""
    base_url = "https://www.wikidata.org/w/api.php"
    params = {
        'action': 'wbsearchentities',
        'search': query,
        'language': 'en',
        'format': 'json',
        'limit': count
    }
    
    url = f"{base_url}?{urllib.parse.urlencode(params)}"
    
    try:
        ssl_context = ssl.create_default_context()
        request = urllib.request.Request(
            url,
            headers={'User-Agent': 'Mozilla/5.0 (OpenClaw Search Tool)'}
        )
        
        with urllib.request.urlopen(request, context=ssl_context, timeout=15) as response:
            data = json.loads(response.read().decode('utf-8'))
            
            results = []
            for entity in data.get('search', []):
                result = {
                    'title': entity.get('label', 'N/A'),
                    'summary': entity.get('description', 'No description available'),
                    'url': entity.get('url', ''),
                    'source': 'Wikidata',
                    'type': 'entity',
                    'wikidata_id': entity.get('title', '')
                }
                results.append(result)
            
            return results
            
    except Exception as e:
        return [{'error': f'Wikidata search failed: {str(e)}'}]

def search_bing(query, count=5):
    """Search using DuckDuckGo JSON API (replaces Bing for reliable JSON responses)"""
    base_url = "https://api.duckduckgo.com"
    params = {
        'q': query,
        'format': 'json',
        'pretty': '1'
    }
    
    url = f"{base_url}?{urllib.parse.urlencode(params)}"
    
    try:
        ssl_context = ssl.create_default_context()
        request = urllib.request.Request(
            url,
            headers={
                'User-Agent': 'Mozilla/5.0 (OpenClaw Search Tool)',
                'Accept': 'application/json'
            }
        )
        
        with urllib.request.urlopen(request, context=ssl_context, timeout=15) as response:
            data = json.loads(response.read().decode('utf-8'))
            
            results = []
            
            # Get the main abstract/summary
            abstract = data.get('Abstract', '')
            if abstract:
                results.append({
                    'title': data.get('Heading', query),
                    'summary': abstract[:300],
                    'url': data.get('Text', ''),
                    'source': 'DuckDuckGo',
                    'type': 'overview'
                })
            
            # Get related topics (web results)
            topics = data.get('RelatedTopics', [])
            for item in topics[:count]:
                result = {
                    'title': item.get('Title', 'N/A'),
                    'summary': item.get('Text', 'No description')[:200],
                    'url': item.get('FirstURL', item.get('URL', '')),
                    'source': 'DuckDuckGo',
                    'type': item.get('Type', 'webpage')
                }
                results.append(result)
            
            return results[:count + 1]  # +1 for the abstract if present
            
    except Exception as e:
        return [{'error': f'DuckDuckGo search failed: {str(e)}'}]

def combined_search(query, count=5, sources=['wikipedia', 'wikidata', 'duckduckgo']):
    """
    Combined search across multiple sources
    
    Args:
        query: Search query string
        count: Number of results per source
        sources: List of sources to search ('wikipedia', 'wikidata', 'duckduckgo')
    
    Returns:
        Dictionary with results from each source
    """
    all_results = {
        'query': query,
        'timestamp': datetime.now().isoformat(),
        'sources': {},
        'summary': []
    }
    
    if 'wikipedia' in sources:
        all_results['sources']['wikipedia'] = search_wikipedia(query, count)
    
    if 'wikidata' in sources:
        all_results['sources']['wikidata'] = search_wikidata(query, count)
    
    if 'duckduckgo' in sources:
        all_results['sources']['duckduckgo'] = search_bing(query, count)
    
    # Create summary of top results
    for source_name, results in all_results['sources'].items():
        if results and 'error' not in results[0]:
            all_results['summary'].append({
                'source': source_name,
                'top_result': results[0]['title'] if results else 'N/A',
                'result_count': len(results)
            })
    
    return all_results

def main():
    """Main entry point for command-line usage"""
    import sys
    
    if len(sys.argv) < 2:
        print("Usage: python3 search_advanced.py <query> [count] [sources]")
        print("  query: Search query string")
        print("  count: Number of results per source (default: 5)")
        print("  sources: Comma-separated list: wikipedia, wikidata, duckduckgo (default: all)")
        return
    
    query = sys.argv[1]
    count = int(sys.argv[2]) if len(sys.argv) > 2 else 5
    
    sources_str = sys.argv[3] if len(sys.argv) > 3 else 'wikipedia,wikidata,duckduckgo'
    sources = [s.strip() for s in sources_str.split(',')]
    
    print(f"\n{'='*80}")
    print(f"Advanced Search Results for: '{query}'")
    print(f"Sources: {', '.join(sources)}")
    print(f"{'='*80}\n")
    
    results = combined_search(query, count, sources)
    
    for source_name, source_results in results['sources'].items():
        print(f"\n{'─'*60}")
        print(f"Source: {source_name.upper()}")
        print(f"{'─'*60}\n")
        
        if not source_results:
            print(f"  [INFO] No results from this source")
            continue
        
        if 'error' in source_results[0]:
            print(f"  [INFO] {source_results[0].get('error', 'Unknown error')}")
            continue
        
        for i, result in enumerate(source_results, 1):
            print(f"  {i}. {result['title']}")
            print(f"     {result['summary'][:150]}")
            print(f"     URL: {result['url'][:80]}")
            print()

if __name__ == "__main__":
    main()
