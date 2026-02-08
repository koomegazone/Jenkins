from flask import Flask, render_template, request, redirect, url_for, jsonify
from datetime import datetime, timedelta
import sqlite3
import os

app = Flask(__name__)

# 데이터베이스 초기화
def init_db():
    conn = sqlite3.connect('library.db')
    c = conn.cursor()
    c.execute('''
        CREATE TABLE IF NOT EXISTS books (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            author TEXT NOT NULL,
            image_url TEXT,
            borrower TEXT,
            borrow_date TEXT,
            return_date TEXT,
            status TEXT DEFAULT 'available'
        )
    ''')
    
    # 샘플 데이터 추가 (테이블이 비어있을 때만)
    c.execute('SELECT COUNT(*) FROM books')
    if c.fetchone()[0] == 0:
        sample_books = [
            ('해리포터와 마법사의 돌', 'J.K. 롤링', 'https://image.yes24.com/goods/118367/XL', None, None, None, 'available'),
            ('반지의 제왕', 'J.R.R. 톨킨', 'https://image.yes24.com/goods/58815/XL', '김철수', '2024-02-01', '2024-02-15', 'borrowed'),
            ('어린왕자', '생텍쥐페리', 'https://image.yes24.com/goods/442862/XL', None, None, None, 'available'),
            ('1984', '조지 오웰', 'https://image.yes24.com/goods/90434296/XL', '이영희', '2024-02-05', '2024-02-19', 'borrowed'),
            ('데미안', '헤르만 헤세', 'https://image.yes24.com/goods/62280/XL', None, None, None, 'available'),
            ('노르웨이의 숲', '무라카미 하루키', 'https://image.yes24.com/goods/64/XL', '박민수', '2024-02-08', '2024-02-22', 'borrowed'),
            ('호밀밭의 파수꾼', 'J.D. 샐린저', 'https://image.yes24.com/goods/2345/XL', None, None, None, 'available'),
            ('위대한 개츠비', 'F. 스콧 피츠제럴드', 'https://image.yes24.com/goods/73660/XL', None, None, None, 'available'),
        ]
        c.executemany('INSERT INTO books (title, author, image_url, borrower, borrow_date, return_date, status) VALUES (?, ?, ?, ?, ?, ?, ?)', sample_books)
    
    conn.commit()
    conn.close()

# 메인 페이지 - 책 목록
@app.route('/')
def index():
    conn = sqlite3.connect('library.db')
    conn.row_factory = sqlite3.Row
    c = conn.cursor()
    
    status_filter = request.args.get('status', 'all')
    search = request.args.get('search', '')
    
    if status_filter == 'all':
        if search:
            c.execute('SELECT * FROM books WHERE title LIKE ? OR author LIKE ? ORDER BY id', 
                     (f'%{search}%', f'%{search}%'))
        else:
            c.execute('SELECT * FROM books ORDER BY id')
    else:
        if search:
            c.execute('SELECT * FROM books WHERE status = ? AND (title LIKE ? OR author LIKE ?) ORDER BY id', 
                     (status_filter, f'%{search}%', f'%{search}%'))
        else:
            c.execute('SELECT * FROM books WHERE status = ? ORDER BY id', (status_filter,))
    
    books = [dict(row) for row in c.fetchall()]
    
    # 통계 계산
    c.execute('SELECT COUNT(*) FROM books WHERE status = "available"')
    available_count = c.fetchone()[0]
    c.execute('SELECT COUNT(*) FROM books WHERE status = "borrowed"')
    borrowed_count = c.fetchone()[0]
    
    conn.close()
    
    return render_template('library_index.html', 
                         books=books, 
                         status_filter=status_filter,
                         search=search,
                         available_count=available_count,
                         borrowed_count=borrowed_count)

# 책 추가 페이지
@app.route('/add')
def add_form():
    return render_template('library_add.html')

# 책 추가 처리
@app.route('/add', methods=['POST'])
def add_book():
    title = request.form.get('title')
    author = request.form.get('author')
    image_url = request.form.get('image_url')
    
    conn = sqlite3.connect('library.db')
    c = conn.cursor()
    c.execute('INSERT INTO books (title, author, image_url, status) VALUES (?, ?, ?, ?)',
              (title, author, image_url, 'available'))
    conn.commit()
    conn.close()
    
    return redirect(url_for('index'))

# 책 대여 처리
@app.route('/borrow/<int:book_id>', methods=['POST'])
def borrow_book(book_id):
    borrower = request.form.get('borrower')
    borrow_date = datetime.now().strftime('%Y-%m-%d')
    return_date = (datetime.now() + timedelta(days=14)).strftime('%Y-%m-%d')
    
    conn = sqlite3.connect('library.db')
    c = conn.cursor()
    c.execute('''UPDATE books 
                 SET borrower = ?, borrow_date = ?, return_date = ?, status = 'borrowed'
                 WHERE id = ?''',
              (borrower, borrow_date, return_date, book_id))
    conn.commit()
    conn.close()
    
    return redirect(url_for('index'))

# 책 반납 처리
@app.route('/return/<int:book_id>', methods=['POST'])
def return_book(book_id):
    conn = sqlite3.connect('library.db')
    c = conn.cursor()
    c.execute('''UPDATE books 
                 SET borrower = NULL, borrow_date = NULL, return_date = NULL, status = 'available'
                 WHERE id = ?''',
              (book_id,))
    conn.commit()
    conn.close()
    
    return redirect(url_for('index'))

# 책 삭제
@app.route('/delete/<int:book_id>', methods=['POST'])
def delete_book(book_id):
    conn = sqlite3.connect('library.db')
    c = conn.cursor()
    c.execute('DELETE FROM books WHERE id = ?', (book_id,))
    conn.commit()
    conn.close()
    
    return redirect(url_for('index'))

# 책 수정 페이지
@app.route('/edit/<int:book_id>')
def edit_form(book_id):
    conn = sqlite3.connect('library.db')
    conn.row_factory = sqlite3.Row
    c = conn.cursor()
    c.execute('SELECT * FROM books WHERE id = ?', (book_id,))
    book = dict(c.fetchone())
    conn.close()
    
    return render_template('library_edit.html', book=book)

# 책 수정 처리
@app.route('/edit/<int:book_id>', methods=['POST'])
def edit_book(book_id):
    title = request.form.get('title')
    author = request.form.get('author')
    image_url = request.form.get('image_url')
    
    conn = sqlite3.connect('library.db')
    c = conn.cursor()
    c.execute('UPDATE books SET title = ?, author = ?, image_url = ? WHERE id = ?',
              (title, author, image_url, book_id))
    conn.commit()
    conn.close()
    
    return redirect(url_for('index'))

if __name__ == '__main__':
    init_db()
    app.run(debug=True, host='0.0.0.0', port=5001)
