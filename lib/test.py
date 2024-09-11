import requests

barcode = "8901548143629"
api_url = f"https://api.barcodelookup.com/v3/products?barcode={barcode}&formatted=y&key=011jqsxvbeteb5ctjk7i4fcye0uyxf"

response = requests.get(api_url)

if response.status_code == 200:
    product_data = response.json()
    if product_data['products']:
        print("Product found:", product_data['products'][0]['title'])
    else:
        print("Product not found.")
else:
    print("API request failed with status code:", response.status_code)
