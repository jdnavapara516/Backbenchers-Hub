def calculate_completed_lines(board_numbers, eliminated_numbers):
    if len(board_numbers) != 25:
        return 0

    marked = set(eliminated_numbers)
    lines = 0

    # Rows
    for row in range(5):
        if all(board_numbers[row * 5 + col] in marked for col in range(5)):
            lines += 1

    # Columns
    for col in range(5):
        if all(board_numbers[row * 5 + col] in marked for row in range(5)):
            lines += 1

    # Diagonals
    if all(board_numbers[i * 5 + i] in marked for i in range(5)):
        lines += 1
    if all(board_numbers[i * 5 + (4 - i)] in marked for i in range(5)):
        lines += 1

    return lines
