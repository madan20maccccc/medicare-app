import urllib.request
import sys

URL_TO_TEST = 'https://huggingface.co/api/models/ncbi-nlp/NCBI_BERT_NER'
TIMEOUT_SECONDS = 15

print(f"Attempting to connect to: {URL_TO_TEST}")
print(f"Timeout set to: {TIMEOUT_SECONDS} seconds")

try:
    with urllib.request.urlopen(URL_TO_TEST, timeout=TIMEOUT_SECONDS) as response:
        print(f'Successfully connected to Hugging Face!')
        print(f'HTTP Status Code: {response.status}')
        print(f'Response Headers (first 5 lines):')
        for i, (header, value) in enumerate(response.getheaders()):
            if i >= 5: break
            print(f'  {header}: {value}')
except urllib.error.URLError as e:
    print(f'Failed to connect to Hugging Face (URLError): {e.reason}')
    print("This often indicates a network issue, DNS problem, or firewall blocking outbound connections.")
except Exception as e:
    print(f'An unexpected error occurred: {e}')
    print("This could be a proxy issue, or another network configuration problem.")